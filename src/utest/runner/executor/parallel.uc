import * as fs from 'fs';
import { ExecutorBase, q, dispatch, build_l_flags } from 'utest.runner.executor.base';
import { mkdir_p } from 'utest.util';

export function create() {
	return proto({
		run: function(shuffled_files, reporter, jobs, filter, bundle_name, run_dir, src_dir, shim_paths, seed, timeout) {
			const WORKER_TIMEOUT_MS = (timeout || 60) * 1000;
			const pipes_dir = run_dir + "/pipes";

			if (!mkdir_p(pipes_dir))
				die("[utest] error: could not create pipes directory: " + pipes_dir);

			let queue = [ ...shuffled_files ];
			let active_workers = [];
			let finished_count = 0;
			let worker_id_counter = 0;

			let lf = build_l_flags(src_dir, shim_paths);

			while (finished_count < length(shuffled_files)) {
				while (length(active_workers) < jobs && length(queue) > 0) {
					let file = shift(queue);
					let id = ++worker_id_counter;
					let out_file = pipes_dir + "/out." + id;
					let done_file = pipes_dir + "/done." + id;
					let pid_file = pipes_dir + "/pid." + id;

					let worker_arg = sprintf('%J', { file: file, filter: filter || null, bundle: bundle_name, seed: seed });
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
						start_time: clock(),
						offset: 0,
						received_any: false
					});
				}

				let still_active = [];
				for (let worker in active_workers) {
					let now = clock();
					let elapsed_ms = (now[0] - worker.start_time[0]) * 1000 +
					                 int((now[1] - worker.start_time[1]) / 1000000);

					if (elapsed_ms > WORKER_TIMEOUT_MS) {
						let pid_raw = fs.readfile(worker.pid_file);
						if (pid_raw) system("kill -9 " + replace(pid_raw, /\s+/, "") + " 2>/dev/null");
						reporter.fatal({ event: "FATAL", suite: worker.file, bundle: bundle_name,
							error: sprintf("worker timed out after %ds", int(WORKER_TIMEOUT_MS / 1000)) });
						finished_count++;
						system("rm -f " + q(worker.out_file) + " " + q(worker.done_file) + " " + q(worker.pid_file));
						continue;
					}

					let fh = fs.open(worker.out_file, "r");
					if (fh) {
						fh.seek(worker.offset, 0);
						let line;
						while ((line = fh.read("line")) != null) {
							if (ord(line, length(line) - 1) != 10) break;
							let msg;
							try { msg = json(line); } catch (e) {
								warn(sprintf("[utest] warning: malformed output from worker (file: %s): %s\n",
									worker.file, rtrim(line)));
								worker.offset += length(line);
								continue;
							}
							dispatch(msg, reporter);
							worker.offset += length(line);
							worker.received_any = true;
						}
						fh.close();
					}

					if (fs.access(worker.done_file, "r")) {
						if (!worker.received_any) {
							let captured = rtrim(fs.readfile(worker.out_file) || "");
							let err = length(captured) > 0
								? "worker produced no test output. Captured:\n" + captured
								: "worker produced no output (possible spawn failure)";
							reporter.fatal({ event: "FATAL", suite: worker.file, bundle: bundle_name, error: err });
						}
						finished_count++;
						system("rm -f " + q(worker.out_file) + " " + q(worker.done_file) + " " + q(worker.pid_file));
					} else {
						push(still_active, worker);
					}
				}
				active_workers = still_active;
				if (finished_count < length(shuffled_files)) sleep(50);
			}
		}
	}, ExecutorBase);
};
