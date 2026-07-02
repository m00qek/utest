import * as fs from 'fs';
import { ExecutorBase, q, build_l_flags, make_stream, worker_arg } from 'utest.runner.executor.base';
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

			// Feed every complete newline-terminated line from fh into the worker's
			// decoder, advancing its byte offset.  A trailing partial line (no
			// newline yet) is left for the next poll — more bytes may still arrive.
			function drain(worker, fh) {
				let line;
				while ((line = fh.read("line")) !== null) {
					if (ord(line, length(line) - 1) !== 10) break;
					worker.stream.feed(line);
					worker.offset += length(line);
				}
			}

			// At terminal time, capture any bytes past the drained offset — a final
			// unterminated line a crashed worker never newline-flushed — so the
			// FATAL diagnostic sees everything the worker wrote, matching the -j1
			// path (whose blocking pipe read surrenders that tail at EOF).
			function capture_tail(worker) {
				let fh = fs.open(worker.out_file, "r");
				if (!fh) return;
				fh.seek(worker.offset, 0);
				worker.stream.capture_raw(fh.read("all") || "");
				fh.close();
			}

			while (finished_count < length(shuffled_files)) {
				while (length(active_workers) < jobs && length(queue) > 0) {
					let file = shift(queue);
					let id = ++worker_id_counter;
					let out_file = pipes_dir + "/out." + id;
					let done_file = pipes_dir + "/done." + id;
					let pid_file = pipes_dir + "/pid." + id;

					let warg = worker_arg(file, ctx);
					// Launch ucode in background inside the subshell so pid_file holds the
					// ucode PID directly — killing it on timeout hits the right process.
					let cmd = sprintf("( ucode %s %s %s > %s 2>&1 & echo $! > %s; wait; touch %s ) &",
						lf.flags, q(lf.worker_path + "/bootstrap.uc"), q(warg), q(out_file), q(pid_file), q(done_file));

					system(cmd);
					push(active_workers, {
						file: file,
						out_file: out_file,
						done_file: done_file,
						pid_file: pid_file,
						start_time: clock(true),
						offset: 0,
						stream: make_stream(reporter)
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
						let tmsg = this.terminal_fatal(worker.stream.terminal(true, int(WORKER_TIMEOUT_MS / 1000)));
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
						// When no protocol output arrived, fold in the unterminated tail so
						// the "produced no test output" diagnostic shows what the worker did
						// write (terminal_fatal ignores `captured` on the other branches).
						if (!worker.stream.received_any) capture_tail(worker);
						let dmsg = this.terminal_fatal(worker.stream.terminal(false, 0));
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
