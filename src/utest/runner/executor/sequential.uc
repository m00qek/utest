import * as fs from 'fs';
import { ExecutorBase, q, dispatch, build_l_flags } from 'utest.runner.executor.base';

export function create() {
	return proto({
		run: function(shuffled_files, reporter, jobs, filter, bundle_name, run_dir, src_dir, shim_paths, seed, timeout, lib_paths) {
			let lf = build_l_flags(src_dir, shim_paths, lib_paths);

			for (let file in shuffled_files) {
				let worker_arg = sprintf('%J', { file: file, filter: filter || null, bundle: bundle_name, seed: seed });
				let cmd = sprintf("ucode %s %s %s",
					lf.flags, q(lf.worker_path + "/bootstrap.uc"), q(worker_arg));
				let proc = fs.popen(cmd, "r");

				if (!proc) {
					reporter.fatal({ event: "FATAL", suite: file, bundle: bundle_name, error: "Failed to spawn worker for " + file });
					continue;
				}

				let line;
				while ((line = proc.read("line")) != null) {
					let msg;
					try { msg = json(line); } catch (e) { continue; }
					dispatch(msg, reporter);
				}
				proc.close();
			}
		}
	}, ExecutorBase);
};
