import * as fs from 'fs';
import { ExecutorBase, q, build_l_flags, make_stream, worker_arg } from 'utest.runner.executor.base';

export function create() {
	return proto({
		run: function(ctx) {
			let reporter = ctx.reporter, bundle_name = ctx.bundle, timeout = ctx.timeout;
			let lf = build_l_flags(ctx.src_dir, ctx.shim_paths, ctx.lib_paths);

			for (let file in ctx.files) {
				let warg = worker_arg(file, ctx);
				// Run worker under a shell watchdog: background it, start a sleep-kill
				// timer, then wait for the worker.  No `timeout` binary is required (not
				// available on all OpenWrt targets).  If the watchdog fires, the worker is
				// SIGTERMed and `wait` exits 143 (128 + 15).  We capture the worker's exit
				// code, then kill the still-sleeping timer ($_S): otherwise, after a fast
				// worker exits and its PID ($_P) is recycled to an unrelated process, the
				// timer's deferred `kill $_P` would fire against that reused PID.  Finally
				// re-exit with the worker's code so timeout detection still works.
				// SIGTERM here (vs the parallel executor's SIGKILL) is deliberate: this
				// path reads the pipe to EOF and needs a distinguishable exit code (143)
				// to tell a timeout from a crash, and `kill` defaults to TERM. The two
				// executors send different signals but the outcome is the same — a worker
				// installs no handler, so either terminates a hung worker, and events are
				// flushed as they are emitted, so nothing buffered is lost either way.
				// `setsid` makes the worker the leader of its own process group (it execs
				// in place, so `$!`/pid tracking is unaffected) so the watchdog can signal
				// the *group* (`-$_P`, negative pid) rather than just the worker: a worker
				// that popens a daemon and hangs would otherwise leave that child holding
				// the pipe's write end open, and our blocking read would never see EOF even
				// after the worker itself died.
				let cmd = sprintf(
					"setsid ucode %s %s %s 2>&1 & _P=$!; (sleep %d; kill -TERM -$_P 2>/dev/null) >/dev/null & _S=$!; wait $_P; _R=$?; kill $_S 2>/dev/null; exit $_R",
					lf.flags, q(lf.worker_path + "/bootstrap.uc"), q(warg), timeout);
				let proc = fs.popen(cmd, "r");

				if (!proc) {
					reporter.fatal({ event: "FATAL", suite: file, bundle: bundle_name, error: "Failed to spawn worker for " + file });
					continue;
				}

				let stream = make_stream(reporter);
				let line;
				// A blocking pipe read yields whole lines, and the final unterminated
				// line at EOF, so every byte reaches the decoder — no separate tail read.
				while ((line = proc.read("line")) !== null)
					stream.feed(line);
				let exit_code = proc.close();
				// 143 = 128 + SIGTERM(15), the exact signal our watchdog sends.  Matching
				// it exactly (rather than >= 128) avoids mislabelling a crashed worker —
				// SIGSEGV(139), SIGABRT(134), SIGKILL/OOM(137) — as a timeout.
				let timed_out = (exit_code === 143);

				// The worker already emitted its own FATAL — don't double-report.
				let smsg = this.terminal_fatal(stream.terminal(timed_out, timeout));
				if (smsg !== null)
					reporter.fatal({ event: "FATAL", suite: file, bundle: bundle_name, error: smsg });
			}
		}
	}, ExecutorBase);
};
