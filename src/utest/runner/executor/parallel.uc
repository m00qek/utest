import * as fs from 'fs';
import { ExecutorBase, q, build_l_flags, make_stream, worker_arg } from 'utest.runner.executor.base';
import { mkdir_p } from 'utest.util';

// Unique across the whole run so per-worker output files never collide between
// bundles that share one run_dir.
let worker_id_counter = 0;

export function create() {
	return proto({
		run: function(ctx) {
			// uloop-only: the parallel executor drives the whole worker lifecycle
			// through the event loop and has no polling fallback. Fail with an
			// actionable message (not a raw require error) when uloop is absent;
			// sequential mode (-j 1) never reaches here and needs no uloop.
			let uloop;
			try {
				uloop = require('uloop');
			} catch (e) {
				die("[utest] error: parallel execution (-j > 1) requires the ucode " +
					"'uloop' module, which could not be loaded. Install it or run without -j.\n");
			}
			const self = this;
			const reporter = ctx.reporter, bundle_name = ctx.bundle, jobs = ctx.jobs;
			const WORKER_TIMEOUT_MS = ctx.timeout * 1000;

			const out_dir = ctx.run_dir + "/workers";
			if (!mkdir_p(out_dir))
				die("[utest] error: could not create worker output directory: " + out_dir);

			const lf = build_l_flags(ctx.src_dir, ctx.shim_paths, ctx.lib_paths);

			let queue = [ ...ctx.files ];
			const total = length(ctx.files);
			let finished = 0;
			let active = 0;
			let running = false;

			// Forward-declared so the mutually-recursive spawn/pump closures can
			// reference each other (ucode does not hoist nested function declarations).
			let finalize, spawn, pump;

			// Feed a finished worker's output — read once from its file — into the
			// shared decoder, then emit any terminal FATAL. Because a worker's whole
			// output is fed in one callback, its events reach the reporter contiguously,
			// with no interleaving between concurrent workers.
			finalize = function(worker, timed_out) {
				const content = fs.readfile(worker.out_file) ?? "";
				// Every protocol event ends in a newline, so split() yields the complete
				// lines plus a trailing segment: "" for a clean end, or an unterminated
				// final line (e.g. a crash mid-write) captured as diagnostic output.
				const parts = split(content, "\n");
				for (let i = 0; i < length(parts) - 1; i++)
					worker.stream.feed(parts[i]);
				const tail = parts[length(parts) - 1];
				if (tail !== "") worker.stream.capture_raw(tail);

				const smsg = self.terminal_fatal(worker.stream.terminal(timed_out, int(WORKER_TIMEOUT_MS / 1000)));
				if (smsg !== null)
					reporter.fatal({ event: "FATAL", suite: worker.file, bundle: bundle_name, error: smsg });

				fs.unlink(worker.out_file);
			};

			spawn = function(file) {
				const id = ++worker_id_counter;
				const out_file = out_dir + "/out." + id;
				const warg = worker_arg(file, ctx);
				let worker = { file, out_file, stream: make_stream(reporter),
				               timer: null, timed_out: false, done: false };

				// Redirect the worker's stdout+stderr to a regular file, read at exit.
				// exec so the pid uloop tracks (and we kill on timeout) is ucode's, not
				// the wrapping shell's. uloop.process builds the child's environment from
				// exactly the given dict (exec-style, NOT inherit-style: {} would exec with
				// an empty envp), so pass the parent's full environment through — otherwise
				// a -jN worker sees no PATH and cannot even find ucode, diverging from -j1.
				// `setsid` makes the worker the leader of its own process group (it execs
				// in place, so the pid uloop tracks is unaffected) so the timeout below can
				// SIGKILL the whole group: otherwise a worker that forked a daemon and hung
				// would leave that child running as an orphan after the worker itself died.
				const cmd = sprintf("exec setsid ucode %s %s %s > %s 2>&1",
					lf.flags, q(lf.worker_path + "/bootstrap.uc"), q(warg), q(out_file));
				const proc = uloop.process("/bin/sh", ["-c", cmd], getenv(), function(code) {
					if (worker.done) return;
					worker.done = true;
					if (worker.timer) { worker.timer.cancel(); worker.timer = null; }
					finalize(worker, worker.timed_out);
					finished++;
					active--;
					pump();
				});

				if (!proc) {
					reporter.fatal({ event: "FATAL", suite: file, bundle: bundle_name,
						error: "Failed to spawn worker for " + file });
					finished++;
					// Do NOT recurse into pump() here: a burst of consecutive synchronous
					// spawn failures (e.g. fd/EMFILE exhaustion) would nest one frame per
					// failure. The enclosing pump() while-loop continues to the next queued
					// file on its own, and its post-loop terminal check closes the run.
					return;
				}

				const pid = proc.pid();
				active++;
				// On timeout, kill the worker; its exit callback then finalizes with the
				// partial output. A SIGKILL exit status is indistinguishable from a clean
				// 0, so the timed_out flag — not the exit code — drives the diagnostic.
				// SIGKILL (not the sequential watchdog's SIGTERM) is deliberate: this path
				// keys the diagnostic on timed_out, so it does not need a distinguishable
				// exit code, and KILL cannot be caught. The signals differ between the two
				// executors but the outcome does not — a worker installs no handler, so
				// either terminates a hung (while(true)) worker identically, and the worker
				// reporter flushes every event, so partial results are already on disk
				// before the signal lands. See sequential.uc for the SIGTERM/exit-143 side.
				// The pid is negated to signal the worker's whole process group (see the
				// `setsid` above) rather than just the ucode process, so a forked child
				// dies with it instead of surviving as an orphan.
				worker.timer = uloop.timer(WORKER_TIMEOUT_MS, function() {
					if (worker.done) return;
					worker.timed_out = true;
					system("kill -9 -" + pid + " 2>/dev/null");
				});
			};

			// Fill every free worker slot, then — once no more can start — close the
			// event loop if every file is accounted for. Called both to prime the run
			// and from each worker's exit callback to refill the slot it freed. Spawn
			// failures increment `finished` inline and stay inside this loop, so a run
			// where every worker fails to spawn still terminates here: the invariant
			// finished + active + len(queue) === total means finished >= total implies
			// both active === 0 and an empty queue.
			pump = function() {
				while (active < jobs && length(queue) > 0)
					spawn(shift(queue));
				if (finished >= total && running)
					uloop.end();
			};

			if (total === 0) return false;
			uloop.init();
			pump();
			// If every worker failed to spawn synchronously, finished already reached
			// total during the priming pump() above (running was still false, so its
			// terminal check did not end a loop that was not yet started); running uloop
			// would then block forever, so only run when work is actually pending.
			let rv = 0;
			if (finished < total) {
				running = true;
				rv = uloop.run();
			}
			// Release uloop's state (registered fds, timers, signal hooks) now that
			// this bundle is done, instead of leaving it for process exit. A run spans
			// multiple bundles, each doing its own init()/run(); pairing every init()
			// with a done() keeps that lifecycle clean and self-contained.
			uloop.done();

			// uloop.run() returns either when pump() called uloop.end() (every
			// worker accounted for) or when libubox caught SIGINT/SIGTERM, set
			// uloop_cancelled, and returned — leaving pending exit callbacks unfired
			// and finished still < total. In that case the interrupted suites would
			// otherwise vanish from the report and the run would exit 0 despite being
			// truncated. Emit a FATAL so the summary is honest and the exit code is
			// non-zero. (Under -j1 a signal kills the runner outright, so this only
			// arises for -jN.)
			// uloop.run() returns 0 on a normal end and the caught signal number on
			// SIGINT/SIGTERM; a non-zero rv, or any pending-worker shortfall, means the
			// run was truncated. Returning `interrupted` tells the runner to stop
			// launching further bundles — otherwise the next bundle's uloop.init()/run()
			// resets uloop_cancelled and spawns a fresh fleet, so the user would need
			// one ^C per remaining bundle.
			let interrupted = (rv !== 0) || (finished < total);
			if (finished < total)
				// aggregate: this FATAL stands for the whole interrupted run, not a
				// real suite, so the reporter must not count "<parallel run>" toward
				// the suite total (it would inflate "Suites:" by one per bundle).
				reporter.fatal({ event: "FATAL", suite: "<parallel run>", bundle: bundle_name, aggregate: true,
					error: sprintf("parallel run interrupted before completion: %d of %d suite(s) did not finish",
						total - finished, total) });
			return interrupted;
		}
	}, ExecutorBase);
};
