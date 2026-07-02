import * as fs from 'fs';
import { ExecutorBase, q, dispatch, build_l_flags } from 'utest.runner.executor.base';
import { mkdir_p } from 'utest.util';

// Monotonic across the whole run. Every bundle shares one run_dir/pipes dir, so
// resetting per bundle reused pipe filenames (out.1/done.1/…) between bundles.
// In practice the timeout cleanup's `rm` beats the killed wrapper's `touch`, so
// no stale done-file survives — but a unique id per worker removes the collision
// class entirely, staying correct even if that cleanup ever fails to complete.
let worker_id_counter = 0;

export function create() {
	return proto({
		run: function(ctx) {
			let reporter = ctx.reporter, bundle_name = ctx.bundle, jobs = ctx.jobs;
			let shuffled_files = ctx.files;
			const WORKER_TIMEOUT_MS = ctx.timeout * 1000;
			const pipes_dir = ctx.run_dir + "/pipes";

			if (!mkdir_p(pipes_dir))
				die("[utest] error: could not create pipes directory: " + pipes_dir);

			let queue = [ ...shuffled_files ];
			let active_workers = [];
			let finished_count = 0;

			let lf = build_l_flags(ctx.src_dir, ctx.shim_paths, ctx.lib_paths);

			// Drain all complete newline-terminated JSON lines from fh into reporter,
			// updating worker state (suite_ended / fatal_received / received_any).
			function drain(worker, fh) {
				let line;
				while ((line = fh.read("line")) !== null) {
					if (ord(line, length(line) - 1) !== 10) break;
					let msg;
					try { msg = json(line); } catch (e) {
						// Non-JSON lines are diagnostic output (e.g. warn() calls
						// from engine.uc). Pass them through to stderr unchanged.
						warn(rtrim(line) + "\n");
						worker.offset += length(line);
						continue;
					}
					// Valid JSON but not an event object (e.g. a test printed a bare
					// number, string, or array): treat as diagnostic output, not a
					// protocol message — dereferencing .event on it would crash the runner.
					if (type(msg) !== "object") {
						warn(rtrim(line) + "\n");
						worker.offset += length(line);
						continue;
					}
					if (msg.event === "SUITE_END") worker.suite_ended = true;
					if (msg.event === "FATAL") worker.fatal_received = true;
					dispatch(msg, reporter);
					worker.offset += length(line);
					worker.received_any = true;
				}
			}

			while (finished_count < length(shuffled_files)) {
				while (length(active_workers) < jobs && length(queue) > 0) {
					let file = shift(queue);
					let id = ++worker_id_counter;
					let out_file = pipes_dir + "/out." + id;
					let done_file = pipes_dir + "/done." + id;
					let pid_file = pipes_dir + "/pid." + id;

					let worker_arg = sprintf('%J', { file: file, filter: ctx.filter || null, bundle: bundle_name, seed: ctx.seed, prop_seed: ctx.prop_seed, mocks: ctx.mocks });
					// Launch ucode in background inside the subshell so pid_file holds the
					// ucode PID directly — killing it on timeout hits the right process.
					let cmd = sprintf("( ucode %s %s %s > %s 2>&1 & echo $! > %s; wait; touch %s ) &",
						lf.flags, q(lf.worker_path + "/bootstrap.uc"), q(worker_arg), q(out_file), q(pid_file), q(done_file));

					system(cmd);
					push(active_workers, {
						file: file,
						out_file: out_file,
						done_file: done_file,
						pid_file: pid_file,
						start_time: clock(true),
						offset: 0,
						received_any: false,
						suite_ended: false,
						fatal_received: false
					});
				}

				let still_active = [];
				for (let worker in active_workers) {
					let now = clock(true);
					let elapsed_ms = (now[0] - worker.start_time[0]) * 1000 +
					                 int((now[1] - worker.start_time[1]) / 1000000);

					if (elapsed_ms > WORKER_TIMEOUT_MS) {
						let pid_raw = fs.readfile(worker.pid_file);
						if (pid_raw) system("kill -9 " + replace(pid_raw, /\s+/, "") + " 2>/dev/null");
						// Drain any output the worker wrote before being killed so partial
						// results are not silently discarded.
						let fh_t = fs.open(worker.out_file, "r");
						if (fh_t) {
							fh_t.seek(worker.offset, 0);
							drain(worker, fh_t);
							fh_t.close();
						}
						// Suppress the timeout fatal if the drain just revealed the worker
						// had actually completed (SUITE_END) or already reported its own
						// fatal right before the deadline — otherwise we double-report.
						let tmsg = this.terminal_fatal({ received_any: worker.received_any,
							suite_ended: worker.suite_ended, fatal_received: worker.fatal_received,
							timed_out: true, timeout: int(WORKER_TIMEOUT_MS / 1000), captured: "" });
						if (tmsg !== null)
							reporter.fatal({ event: "FATAL", suite: worker.file, bundle: bundle_name, error: tmsg });
						finished_count++;
						system("rm -f " + q(worker.out_file) + " " + q(worker.done_file) + " " + q(worker.pid_file));
						continue;
					}

					let fh = fs.open(worker.out_file, "r");
					if (fh) {
						fh.seek(worker.offset, 0);
						drain(worker, fh);
						fh.close();
					}

					if (fs.access(worker.done_file, "r")) {
						// Second drain: pick up any lines the worker wrote after our last
						// read loop finished but before we noticed done_file.
						let fh2 = fs.open(worker.out_file, "r");
						if (fh2) {
							fh2.seek(worker.offset, 0);
							drain(worker, fh2);
							fh2.close();
						}
						// The worker already emitted its own FATAL — don't pile a second one
						// on top.  Only flag missing output or an unexplained early exit.
						let captured = !worker.received_any ? rtrim(fs.readfile(worker.out_file) || "") : "";
						let dmsg = this.terminal_fatal({ received_any: worker.received_any,
							suite_ended: worker.suite_ended, fatal_received: worker.fatal_received,
							timed_out: false, timeout: 0, captured: captured });
						if (dmsg !== null)
							reporter.fatal({ event: "FATAL", suite: worker.file, bundle: bundle_name, error: dmsg });
						finished_count++;
						system("rm -f " + q(worker.out_file) + " " + q(worker.done_file) + " " + q(worker.pid_file));
					} else {
						push(still_active, worker);
					}
				}
				active_workers = still_active;
				if (finished_count < length(shuffled_files)) {
					// Sleep at most 50 ms, but wake sooner if a worker is about to time out.
					let wait_ms = 50;
					let now = clock(true);
					for (let w in active_workers) {
						let elapsed = (now[0] - w.start_time[0]) * 1000 +
						              int((now[1] - w.start_time[1]) / 1000000);
						let remaining = WORKER_TIMEOUT_MS - elapsed;
						if (remaining > 0 && remaining < wait_ms) wait_ms = remaining;
					}
					sleep(wait_ms);
				}
			}
		}
	}, ExecutorBase);
};
