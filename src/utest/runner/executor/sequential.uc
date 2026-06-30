import * as fs from 'fs';
import { ExecutorBase, q, dispatch, build_l_flags } from 'utest.runner.executor.base';

export function create() {
	return proto({
		run: function(shuffled_files, reporter, jobs, filter, bundle_name, run_dir, src_dir, shim_paths, seed, timeout, lib_paths, mocks, prop_seed) {
			let lf = build_l_flags(src_dir, shim_paths, lib_paths);

			for (let file in shuffled_files) {
				let worker_arg = sprintf('%J', { file: file, filter: filter || null, bundle: bundle_name, seed: seed, prop_seed: prop_seed, mocks: mocks || [] });
				// Run worker under a shell watchdog: background it, start a sleep-kill
				// timer, then wait for whichever finishes first.  No `timeout` binary is
				// required (not available on all OpenWrt targets).  If the watchdog fires,
				// the worker is SIGTERMed and `wait` exits with 143 (128 + 15).
				let cmd = sprintf(
					"ucode %s %s %s 2>&1 & _P=$!; (sleep %d; kill $_P 2>/dev/null) >/dev/null & wait $_P",
					lf.flags, q(lf.worker_path + "/bootstrap.uc"), q(worker_arg), timeout);
				let proc = fs.popen(cmd, "r");

				if (!proc) {
					reporter.fatal({ event: "FATAL", suite: file, bundle: bundle_name, error: "Failed to spawn worker for " + file });
					continue;
				}

				let line;
				let received_any = false;
				let suite_ended = false;
				let captured = [];
				while ((line = proc.read("line")) !== null) {
					let msg;
					try { msg = json(line); } catch (e) {
						warn(rtrim(line) + "\n");
						push(captured, rtrim(line));
						continue;
					}
					if (msg.event === "SUITE_END") suite_ended = true;
					dispatch(msg, reporter);
					received_any = true;
				}
				let exit_code = proc.close();

				if (!received_any) {
					let timed_out = (type(exit_code) === 'int' && exit_code >= 128);
					let err = timed_out
						? sprintf("worker timed out after %ds", timeout)
						: length(captured) > 0
							? "worker produced no test output. Captured:\n" + join("\n", captured)
							: "worker produced no output (possible spawn failure)";
					reporter.fatal({ event: "FATAL", suite: file, bundle: bundle_name, error: err });
				} else if (!suite_ended) {
					let timed_out = (type(exit_code) === 'int' && exit_code >= 128);
					reporter.fatal({ event: "FATAL", suite: file, bundle: bundle_name,
						error: timed_out
							? sprintf("worker timed out after %ds (partial results above)", timeout)
							: "worker terminated before completing (partial results above)" });
				}
			}
		}
	}, ExecutorBase);
};
