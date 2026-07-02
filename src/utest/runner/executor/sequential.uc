import * as fs from 'fs';
import { ExecutorBase, q, dispatch, build_l_flags } from 'utest.runner.executor.base';

export function create() {
	return proto({
		run: function(shuffled_files, reporter, jobs, filter, bundle_name, run_dir, src_dir, shim_paths, seed, timeout, lib_paths, mocks, prop_seed) {
			let lf = build_l_flags(src_dir, shim_paths, lib_paths);

			for (let file in shuffled_files) {
				let worker_arg = sprintf('%J', { file: file, filter: filter || null, bundle: bundle_name, seed: seed, prop_seed: prop_seed, mocks: mocks || [] });
				// Run worker under a shell watchdog: background it, start a sleep-kill
				// timer, then wait for the worker.  No `timeout` binary is required (not
				// available on all OpenWrt targets).  If the watchdog fires, the worker is
				// SIGTERMed and `wait` exits 143 (128 + 15).  We capture the worker's exit
				// code, then kill the sleep timer so it does not linger as an orphaned
				// process (a PID-table leak when many fast tests run in sequence), and
				// finally re-exit with the worker's code so timeout detection still works.
				let cmd = sprintf(
					"ucode %s %s %s 2>&1 & _P=$!; (sleep %d; kill $_P 2>/dev/null) >/dev/null & _S=$!; wait $_P; _R=$?; kill $_S 2>/dev/null; exit $_R",
					lf.flags, q(lf.worker_path + "/bootstrap.uc"), q(worker_arg), timeout);
				let proc = fs.popen(cmd, "r");

				if (!proc) {
					reporter.fatal({ event: "FATAL", suite: file, bundle: bundle_name, error: "Failed to spawn worker for " + file });
					continue;
				}

				let line;
				let received_any = false;
				let suite_ended = false;
				let fatal_received = false;
				let captured = [];
				while ((line = proc.read("line")) !== null) {
					let msg;
					try { msg = json(line); } catch (e) {
						warn(rtrim(line) + "\n");
						push(captured, rtrim(line));
						continue;
					}
					// Valid JSON but not an event object (e.g. a test printed a bare
					// number, string, or array): treat as diagnostic output, not a
					// protocol message — dereferencing .event on it would crash the runner.
					if (type(msg) !== "object") {
						warn(rtrim(line) + "\n");
						push(captured, rtrim(line));
						continue;
					}
					if (msg.event === "SUITE_END") suite_ended = true;
					if (msg.event === "FATAL") fatal_received = true;
					dispatch(msg, reporter);
					received_any = true;
				}
				let exit_code = proc.close();
				// 143 = 128 + SIGTERM(15), the exact signal our watchdog sends.  Matching
				// it exactly (rather than >= 128) avoids mislabelling a crashed worker —
				// SIGSEGV(139), SIGABRT(134), SIGKILL/OOM(137) — as a timeout.
				let timed_out = (exit_code === 143);

				// The worker already emitted its own FATAL — don't double-report.
				let smsg = this.terminal_fatal({ received_any: received_any, suite_ended: suite_ended,
					fatal_received: fatal_received, timed_out: timed_out, timeout: timeout,
					captured: join("\n", captured) });
				if (smsg !== null)
					reporter.fatal({ event: "FATAL", suite: file, bundle: bundle_name, error: smsg });
			}
		}
	}, ExecutorBase);
};
