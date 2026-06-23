import { popen, readfile } from 'fs';
const _util = loadfile("test/util.uc")();
const deep_equal = _util.deep_equal;
const format_path = _util.format_path;

/**
 * Total Verification Harness
 * Compares framework output against baseline JSON test-by-test.
 * Now verifies EVERY test result (PASS, FAIL, ERROR, SKIP).
 */

function normalize(obj) {
    if (type(obj) !== "object") return obj;
    let n = { ...obj };
    delete n.duration_ms;
    delete n.seed;
    for (let k, v in n) {
        if (type(v) === "object") n[k] = normalize(v);
        else if (type(v) === "array") {
            n[k] = [];
            for (let item in v) push(n[k], normalize(item));
        }
    }
    return n;
}

function get_test_path(test) {
    if (!test.path) return "Unknown Test";
    return format_path(test.path);
}

// Sort by (suite, index) for stable comparison across FATAL events (no index)
// and multi-bundle runs (duplicate indices from independent workers).
function cmp_results(a, b) {
    let sa = a.suite || "";
    let sb = b.suite || "";
    if (sa < sb) return -1;
    if (sa > sb) return 1;
    return (a.index || 0) - (b.index || 0);
}

function main() {
    let example_file = ARGV[0];
    let expected_file = ARGV[1];
    let extra_flags = ARGV[2] || "";

    if (!example_file || !expected_file) exit(1);

    // 1. Execute Framework
    let cmd = sprintf("utest -r json %s %s", extra_flags, example_file);
    let proc = popen(cmd);
    let actual_raw = proc.read("all");
    let raw_status = proc.close();

    let actual_json = json(actual_raw);
    if (!actual_json) {
        print(sprintf("  [FAIL] %s (Could not parse JSON output)\n", example_file));
        exit(1);
    }

    // 2. Load Expected Baseline
    let expected_json = json(readfile(expected_file));
    if (!expected_json) {
        print(sprintf("  [FAIL] %s (Could not load baseline JSON)\n", expected_file));
        exit(1);
    }

    let all_pass = true;

    // 3. Verify Global Stats
    let a_stats = normalize(actual_json.stats);
    let e_stats = normalize(expected_json.stats);
    if (deep_equal(a_stats, e_stats)) {
        print(sprintf("  [PASS] %s (Global Stats)\n", example_file));
    } else {
        print(sprintf("  [FAIL] %s (Stats Mismatch)\n", example_file));
        print(sprintf("         Expected: %J\n         Actual:   %J\n", e_stats, a_stats));
        all_pass = false;
    }

    // 3b. Verify exit code matches failure status in the baseline.
    let expected_nonzero = (e_stats.failed > 0 || e_stats.errors > 0 || e_stats.fatals > 0);
    let actual_nonzero = (raw_status !== 0);
    if (actual_nonzero === expected_nonzero) {
        print(sprintf("  [PASS] %s (Exit Code)\n", example_file));
    } else {
        print(sprintf("  [FAIL] %s (Exit Code: expected %s, got raw status %d)\n",
            example_file, expected_nonzero ? "non-zero" : "0", raw_status));
        all_pass = false;
    }

    // 4. Verify EVERY individual test result
    let a_results = normalize(actual_json.results || []);
    let e_results = normalize(expected_json.results || []);

    sort(a_results, cmp_results);
    sort(e_results, cmp_results);

    if (length(e_results) > 0) {
        for (let i = 0; i < length(e_results); i++) {
            let e = e_results[i];
            let a = a_results[i];
            let test_path = get_test_path(e);

            if (a && deep_equal(a, e)) {
                print(sprintf("  [PASS] %s > %s (%s)\n", example_file, test_path, e.status || e.event));
            } else {
                print(sprintf("  [FAIL] %s > %s (%s)\n", example_file, test_path, e.status || e.event));
                all_pass = false;
            }
        }
    }

    exit(all_pass ? 0 : 1);
}

main();
