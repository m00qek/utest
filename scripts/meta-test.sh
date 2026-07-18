#!/bin/sh

# Find the absolute path of the project root, then run from it. The baseline
# discovery (`find examples`), the `[ -f "$json_path" ]` checks, and companion
# config detection all resolve against the cwd, while the docker mounts use
# $PROJECT_ROOT; without this cd, running the script from another directory would
# silently find no baselines and still print SUCCESS from the hardcoded blocks.
PROJECT_ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$PROJECT_ROOT" || exit 1

# Test rootfs image must include ucode with the uloop module (the parallel
# executor requires it; there is no polling fallback). Newer rootfs tags use the
# full version and drop the '-openwrt-' infix.
SDK_ARCH=${SDK_ARCH:-x86-64}
ROOTFS_VERSION=${ROOTFS_VERSION:-25.12.4}
IMAGE_OPENWRT=${IMAGE_OPENWRT:-openwrt/rootfs:${SDK_ARCH}-${ROOTFS_VERSION}}

# Execute the verification harness inside the Docker environment
run_verify() {
    example=$1
    expected=$2
    extra_flags=${3:-""}
    docker_env=${4:-""}
    # Map the host uid/gid so any files the run touches under the bind-mounted
    # repo are host-owned, not root. --tmpfs gives a writable /tmp for utest.sh's
    # mktemp run dir (newer rootfs images ship /tmp as 0755 root-owned).
    # $docker_env is intentionally unquoted so "-e VAR=val" splits into flags.
    docker run --rm \
        --user "$(id -u):$(id -g)" \
        --tmpfs /tmp:mode=1777 \
        $docker_env \
        -v "$PROJECT_ROOT/src/utest.sh:/usr/bin/utest:ro" \
        -v "$PROJECT_ROOT/src/utest.uc:/usr/share/ucode/utest.uc:ro" \
        -v "$PROJECT_ROOT/src/utest:/usr/share/ucode/utest:ro" \
        -v "$PROJECT_ROOT:/app" \
        -w /app \
        "$IMAGE_OPENWRT" \
        ucode test/verify.uc "$example" "$expected" "$extra_flags"
}

# Smoke-test a human-facing reporter (detailed/compact). verify.uc only speaks
# -r json, so these ~230 lines otherwise ship unexecuted. Asserts: exit code
# matches, output is non-empty, no runner stack trace leaked, and each expected
# token is present. Color is disabled (test/nocolor.config.uc) for stable output.
# Extra utest flags may be passed via $SMOKE_EXTRA (unquoted, so it word-splits).
#   smoke_reporter <reporter> <fixture> <expected_exit> [token...]
smoke_reporter() {
    reporter=$1; fixture=$2; expected_exit=$3; shift 3
    out=$(docker run --rm \
        --user "$(id -u):$(id -g)" \
        --tmpfs /tmp:mode=1777 \
        -v "$PROJECT_ROOT/src/utest.sh:/usr/bin/utest:ro" \
        -v "$PROJECT_ROOT/src/utest.uc:/usr/share/ucode/utest.uc:ro" \
        -v "$PROJECT_ROOT/src/utest:/usr/share/ucode/utest:ro" \
        -v "$PROJECT_ROOT:/app" \
        -w /app \
        "$IMAGE_OPENWRT" \
        utest -r "$reporter" -c test/nocolor.config.uc ${SMOKE_EXTRA:-} "$fixture" 2>&1)
    ec=$?
    label="reporter[$reporter] ${fixture#examples/}"
    ok=1
    [ "$ec" -eq "$expected_exit" ] || { echo "  [FAIL] $label (exit $ec, expected $expected_exit)"; ok=0; }
    [ -n "$out" ] || { echo "  [FAIL] $label (empty output)"; ok=0; }
    if printf '%s\n' "$out" | grep -q "called from function"; then
        echo "  [FAIL] $label (runner stack trace in output)"; ok=0
    fi
    for tok in "$@"; do
        printf '%s\n' "$out" | grep -qF "$tok" || { echo "  [FAIL] $label (missing token: $tok)"; ok=0; }
    done
    [ "$ok" -eq 1 ] && echo "  [PASS] $label (smoke)"
    return $(( ! ok ))
}

# Assert utest rejects an invalid CLI/config value: non-zero exit and a matching
# message. These validations die before any JSON is produced, so verify.uc (which
# parses JSON) cannot cover them — check at the shell level.
#   assert_cli_error <label> <expected-substring> <utest args...>
assert_cli_error() {
    label=$1; expect=$2; shift 2
    out=$(docker run --rm \
        --user "$(id -u):$(id -g)" \
        --tmpfs /tmp:mode=1777 \
        -v "$PROJECT_ROOT/src/utest.sh:/usr/bin/utest:ro" \
        -v "$PROJECT_ROOT/src/utest.uc:/usr/share/ucode/utest.uc:ro" \
        -v "$PROJECT_ROOT/src/utest:/usr/share/ucode/utest:ro" \
        -v "$PROJECT_ROOT:/app" -w /app \
        "$IMAGE_OPENWRT" \
        utest "$@" examples/unit/01_assertions_test.uc 2>&1)
    ec=$?
    ok=1
    [ "$ec" -ne 0 ] || { echo "  [FAIL] cli-error[$label] (expected non-zero exit)"; ok=0; }
    printf '%s\n' "$out" | grep -qF "$expect" || { echo "  [FAIL] cli-error[$label] (missing: $expect)"; ok=0; }
    [ "$ok" -eq 1 ] && echo "  [PASS] cli-error[$label]"
    return $(( ! ok ))
}

failed_tests=""

printf 'Verification Started\n\n'

# Find all example tests
temp_list=$(mktemp)
find examples -name "*_test.uc" | sort > "$temp_list"

while read f; do
    rel_path=${f#examples/}
    json_path="test/json/${rel_path%.uc}.json"
    
    if [ ! -f "$json_path" ]; then
        # envprobe/, multi/, and timeout/ carry no per-file baseline on purpose —
        # they are verified by the dedicated blocks below. Any OTHER file without a
        # baseline is a regression (a deleted baseline, or a test renamed without
        # renaming its baseline) and must fail, not silently drop from the run.
        case "$rel_path" in
            envprobe/*|multi/*|timeout/*)
                echo "  [SKIP] $f (verified in a dedicated block)" ;;
            *)
                echo "  [FAIL] $f (missing baseline: $json_path)"
                failed_tests="$failed_tests $f" ;;
        esac
        continue
    fi

    # Pass custom bundle name for the bundle test
    bundle_arg="$f"
    if [ "$rel_path" = "unit/08_bundles_test.uc" ]; then
        bundle_arg="MyBundle:$f"
    fi

    # Detect companion config file (e.g. 10_standard_shim_config.uc alongside 10_standard_shim_test.uc)
    config_flags=""
    companion_config="examples/${rel_path%_test.uc}_config.uc"
    if [ -f "$companion_config" ]; then
        config_flags="-c $companion_config"
    fi

    if run_verify "$bundle_arg" "$json_path" "$config_flags"; then
        :
    else
        failed_tests="$failed_tests $f"
    fi
done < "$temp_list"

rm "$temp_list"

# Multi-bundle run: exercises cross-bundle stat aggregation and the bundles{} map.
# The two test files in examples/multi/ have no individual baselines so the main loop
# skips them; they are verified here as a combined two-bundle invocation.
#
# The space-separated value is passed as a single shell word to run_verify, which
# forwards it as ARGV[0] to verify.uc.  verify.uc interpolates it into a shell
# command string, so the shell splits it into two separate utest arguments.
# This relies on the paths containing no spaces.
multi_arg="BundleA:examples/multi/01_bundle_a_test.uc BundleB:examples/multi/02_bundle_b_test.uc"
if run_verify "$multi_arg" "test/json/multi/bundle_test.json"; then
    :
else
    failed_tests="$failed_tests multi_bundle"
fi

# Parallel run: exercises the parallel executor (-j 2) using the same
# examples/multi/ files as the multi-bundle test, but as a single bundle.
# Results arrive in nondeterministic order; verify.uc's (suite, index) sort
# makes the comparison stable.
if run_verify "examples/multi/" "test/json/multi/parallel_test.json" "-j 2"; then
    :
else
    failed_tests="$failed_tests parallel_test"
fi

# Timeout under parallel + multi-bundle: one bundle's worker hangs forever and is
# killed by the configured timeout (2s, via the companion config), reported as a
# FATAL, while a sibling bundle's worker passes. Exercises the uloop executor's
# per-worker timeout path and deterministic "worker timed out after Ns" message.
# The hang fixture runs three quick checks before hanging, so the baseline also
# pins that their results survive the timeout kill — the worker reporter flushes
# each event, so partial results reach the parent before SIGKILL/SIGTERM. `-s 7`
# fixes the shuffle so the hang always lands last and the captured trio is stable.
# The two files have no individual baselines so the main loop skips them.
timeout_arg="Pass:examples/timeout/01_pass_test.uc Hang:examples/timeout/02_hang_test.uc"
if run_verify "$timeout_arg" "test/json/timeout/timeout_test.json" "-j 2 -s 7 -c examples/timeout/timeout.config.uc"; then
    :
else
    failed_tests="$failed_tests timeout_test"
fi

# Same timeout scenario under -j 1: exercises the SEQUENTIAL executor's shell
# watchdog (sleep-kill -> SIGTERM -> exit 143) and its exact-143 timeout
# detection, which the parallel (uloop) path above does not cover.
if run_verify "$timeout_arg" "test/json/timeout/timeout_seq_test.json" "-j 1 -s 7 -c examples/timeout/timeout.config.uc"; then
    :
else
    failed_tests="$failed_tests timeout_seq_test"
fi

# Process-group kill: a worker that forks a background grandchild before
# hanging must not leave it running once the timeout kill fires. The
# sequential executor's blocking pipe read only unblocks once every writer of
# the pipe closes, so a surviving grandchild would stall the run for its full
# 30s lifetime instead of completing within the 2s timeout (checked via wall
# clock, since the JSON output itself is identical either way — the "timed
# out" diagnostic is decided before the read unblocks); the parallel executor
# would leave it running as an orphan (checked via pgrep, anchored so it
# cannot match the wrapper shell's own command line, which contains the same
# literal text). `timeout 40` is a CI safety net, not the mechanism under
# test — the fixture's own `sleep 30` bounds a regression to a slow test, not
# an infinite one.
grandchild_arg="Pass:examples/timeout/01_pass_test.uc Grandchild:examples/timeout/03_grandchild_test.uc"
check_process_group_kill() {
    j=$1
    inner="utest -r json -j $j -s 7 -c examples/timeout/timeout.config.uc $grandchild_arg; sleep 1; pgrep -f '^sleep 30' >/dev/null 2>&1 && echo UTEST_ORPHAN_FOUND || echo UTEST_ORPHAN_NONE"
    start=$(date +%s)
    out=$(timeout 40 docker run --rm \
        --user "$(id -u):$(id -g)" \
        --tmpfs /tmp:mode=1777 \
        -v "$PROJECT_ROOT/src/utest.sh:/usr/bin/utest:ro" \
        -v "$PROJECT_ROOT/src/utest.uc:/usr/share/ucode/utest.uc:ro" \
        -v "$PROJECT_ROOT/src/utest:/usr/share/ucode/utest:ro" \
        -v "$PROJECT_ROOT:/app" -w /app \
        "$IMAGE_OPENWRT" \
        sh -c "$inner" 2>&1)
    elapsed=$(( $(date +%s) - start ))
    ok=1
    [ "$elapsed" -le 10 ] || { echo "  [FAIL] process-group-kill[-j$j] (took ${elapsed}s, expected <=10s)"; ok=0; }
    printf '%s\n' "$out" | grep -qF "worker timed out after" || { echo "  [FAIL] process-group-kill[-j$j] (missing timeout diagnostic)"; ok=0; }
    printf '%s\n' "$out" | grep -q "UTEST_ORPHAN_NONE" || { echo "  [FAIL] process-group-kill[-j$j] (grandchild survived the timeout kill)"; ok=0; }
    [ "$ok" -eq 1 ] && echo "  [PASS] process-group-kill[-j$j] (${elapsed}s, no orphan)"
    return $(( ! ok ))
}
for j in 1 2; do
    check_process_group_kill "$j" || failed_tests="$failed_tests process_group_kill_j$j"
done

# json_str control-char escaping: a raw tab/CR/newline in a -f/-c/-l argument
# must produce genuinely valid JSON for the hand-rolled `opts` blob utest.sh
# passes to cli.uc. ucode's own json() tolerates a raw control character
# inside a string (verified live against the interpreter — it is not a strict
# RFC 8259 parser), so a round-trip through the CLI would not catch a
# regression here; jq (strict) is used instead, against the helper directly
# (the extraction assumes json_str keeps a standalone closing-brace line).
check_json_str_escaping() {
    fn=$(mktemp)
    sed -n '/^json_str()/,/^}/p' "$PROJECT_ROOT/src/utest.sh" > "$fn"
    payload=$(printf 'foo\tbar\rbaz\nqux\\end"quote')
    out=$(docker run --rm -v "$fn:/json_str.sh:ro" "$IMAGE_OPENWRT" \
        sh -c '. /json_str.sh; json_str "$1"' -- "$payload" 2>&1)
    rm -f "$fn"
    ok=1
    printf '{"v":%s}\n' "$out" | jq empty >/dev/null 2>&1 \
        || { echo "  [FAIL] json-str-escaping (invalid JSON for a control-char payload)"; ok=0; }
    got=$(printf '{"v":%s}' "$out" | jq -r .v 2>/dev/null)
    [ "$got" = "$payload" ] \
        || { echo "  [FAIL] json-str-escaping (round-trip mismatch)"; ok=0; }
    [ "$ok" -eq 1 ] && echo "  [PASS] json-str-escaping (tab/CR/newline/backslash/quote round-trip via jq)"
    return $(( ! ok ))
}
check_json_str_escaping || failed_tests="$failed_tests json_str_escaping"

# Env passthrough (1.1): a -jN worker is spawned via uloop.process, which is
# exec-style — it builds the child environment from exactly the dict it is given,
# so an empty dict would leave the worker with no environment (no PATH -> cannot
# even find ucode), silently diverging from -j1. The probe fixture asserts a
# custom variable set on the parent is visible; running it identically under -j1
# (in-process) and -j2 (through a spawned worker) against one baseline pins the
# invariant. A custom var (not PATH) is used because the container ships a shell
# fallback PATH that would mask a truly empty envp.
for j in 1 2; do
    if run_verify "examples/envprobe/01_env_test.uc" "test/json/envprobe/env_probe.json" \
        "-j $j" "-e UTEST_ENV_PROBE=present"; then
        :
    else
        failed_tests="$failed_tests env_probe_j$j"
    fi
done

# CLI/config coercion validation (1.12): a bad -j silently became sequential, a
# bad -s became seed 0, and a misspelled config reporter fell through to default.
assert_cli_error "bad-jobs"     "expected a positive integer" -j abc \
    || failed_tests="$failed_tests cli_bad_jobs"
assert_cli_error "bad-seed"     "expected an integer"         -s xyz \
    || failed_tests="$failed_tests cli_bad_seed"
assert_cli_error "bad-reporter" "expected one of"             -r bogus \
    || failed_tests="$failed_tests cli_bad_reporter"
# An unknown flag and a nonexistent config must fail loudly, not be ignored.
assert_cli_error "unknown-flag"  "Unknown option"             -Z \
    || failed_tests="$failed_tests cli_unknown_flag"
assert_cli_error "missing-config" "Configuration file not found" -c /no/such/config.uc \
    || failed_tests="$failed_tests cli_missing_config"

# -l flag with a RELATIVE path: a `-l` argument arrives relative to the
# invocation cwd, but the worker runs from a different cwd, so a relative `-L`
# never resolved there — the flag only worked with an absolute path. cli.uc now
# makes each `-l` path absolute against the cwd. Reuse the config-lib-paths
# helper (a `greeting` module) but supply it via the flag, not the config, so
# the module resolves ONLY if the relative `-l` path was made absolute. The
# tutorials (`utest -l src ...`) depend on this working.
check_lib_flag() {
    out=$(docker run --rm --user "$(id -u):$(id -g)" --tmpfs /tmp:mode=1777 \
        -v "$PROJECT_ROOT/src/utest.sh:/usr/bin/utest:ro" \
        -v "$PROJECT_ROOT/src/utest.uc:/usr/share/ucode/utest.uc:ro" \
        -v "$PROJECT_ROOT/src/utest:/usr/share/ucode/utest:ro" \
        -v "$PROJECT_ROOT:/app" -w /app \
        "$IMAGE_OPENWRT" \
        utest -r json -l examples/unit/config_lib_paths_helper \
            examples/unit/20_config_lib_paths_test.uc 2>&1)
    ec=$?
    ok=1
    [ "$ec" -eq 0 ] || { echo "  [FAIL] lib-flag[-l relative] (exit $ec)"; ok=0; }
    printf '%s\n' "$out" | grep -q '"failed": 0' && printf '%s\n' "$out" | grep -q '"passed": 1' \
        || { echo "  [FAIL] lib-flag[-l relative] (greeting module did not resolve via relative -l)"; ok=0; }
    [ "$ok" -eq 1 ] && echo "  [PASS] lib-flag[-l relative] (relative -l path resolves against cwd)"
    return $(( ! ok ))
}
check_lib_flag || failed_tests="$failed_tests lib_flag_relative"

# Reporter smoke tests: the detailed and compact reporters have no JSON baseline,
# so cover their PASS / FAIL+ERROR / FATAL rendering paths (a crash here would
# otherwise ship silently — the class of bug fixed in the decoder guard).
for rep in compact detailed; do
    smoke_reporter "$rep" examples/unit/06_diagnostics_test.uc 1 "is a failure" "is an error" \
        || failed_tests="$failed_tests reporter_${rep}_diagnostics"
    smoke_reporter "$rep" examples/unit/22_fatal_setup_test.uc 1 "Module setup failed: intentional" \
        || failed_tests="$failed_tests reporter_${rep}_fatal"
    smoke_reporter "$rep" examples/unit/01_assertions_test.uc 0 "Summary" \
        || failed_tests="$failed_tests reporter_${rep}_pass"
done

# Module-load failure: a test file that fails to COMPILE (here, a bad import) must
# surface as a FATAL with a non-zero exit — not vanish silently, and not spill a
# raw runner stack trace. 22_fatal_setup covers a *runtime* setup fatal; this is
# the earlier compile/load path. The fixture is named without the _test.uc suffix
# so the main discovery loop skips it (it has, and needs, no JSON baseline).
smoke_reporter detailed examples/loadfail/broken_import.uc 1 \
    "Unable to compile source file" "Fatals:  1" \
    || failed_tests="$failed_tests reporter_load_fatal"

# SKIP / IGNORE rendering (3.5): the smoke set above covers PASS/FAIL/ERROR/FATAL
# but not skipped or ignored tests in either reporter. Detailed labels them
# [SKIP]/[IGNORE]; compact shows them only in the summary counts.
smoke_reporter detailed examples/unit/04_skipping_test.uc 0 "[SKIP]" \
    || failed_tests="$failed_tests reporter_detailed_skip"
smoke_reporter compact  examples/unit/04_skipping_test.uc 0 "skipped" \
    || failed_tests="$failed_tests reporter_compact_skip"
# A filter that matches nothing turns every test into IGNORE.
SMOKE_EXTRA="-f ZZZ_no_match"
smoke_reporter detailed examples/unit/01_assertions_test.uc 0 "[IGNORE]" \
    || failed_tests="$failed_tests reporter_detailed_ignore"
smoke_reporter compact  examples/unit/01_assertions_test.uc 0 "ignored" \
    || failed_tests="$failed_tests reporter_compact_ignore"
SMOKE_EXTRA=""

# -j2 rendering contiguity (3.2): under parallel execution the detailed reporter
# streams each worker's events live, relying on the executor feeding a worker's
# whole output to the decoder in one callback so events never interleave between
# concurrent workers. Run the two multi/ suites at -j2 and assert each suite
# header appears exactly once — the buffering-removal invariant would otherwise
# split or duplicate a header.
smoke_parallel_contiguity() {
    out=$(docker run --rm \
        --user "$(id -u):$(id -g)" \
        --tmpfs /tmp:mode=1777 \
        -v "$PROJECT_ROOT/src/utest.sh:/usr/bin/utest:ro" \
        -v "$PROJECT_ROOT/src/utest.uc:/usr/share/ucode/utest.uc:ro" \
        -v "$PROJECT_ROOT/src/utest:/usr/share/ucode/utest:ro" \
        -v "$PROJECT_ROOT:/app" -w /app \
        "$IMAGE_OPENWRT" \
        utest -r detailed -c test/nocolor.config.uc -j 2 examples/multi/ 2>&1)
    ok=1
    printf '%s\n' "$out" | grep -q "called from function" && { echo "  [FAIL] parallel-contiguity (stack trace)"; ok=0; }
    for suite in 01_bundle_a_test.uc 02_bundle_b_test.uc; do
        n=$(printf '%s\n' "$out" | grep -cF "$suite")
        [ "$n" -eq 1 ] || { echo "  [FAIL] parallel-contiguity ($suite header appears $n times, expected 1)"; ok=0; }
    done
    [ "$ok" -eq 1 ] && echo "  [PASS] parallel-contiguity (each -j2 suite header exactly once)"
    return $(( ! ok ))
}
smoke_parallel_contiguity || failed_tests="$failed_tests parallel_contiguity"

# dup-file-across-bundles: the same file named in two different bundles must
# get its own header and its own suite-stats bucket, not have the second
# bundle's occurrence merged into (and suppressed by) the first's. _suite_stats
# / reported_suites used to key on file path alone, shared across the whole
# run; keyed on (bundle, file) now.
check_dup_file_across_bundles() {
    out=$(docker run --rm \
        --user "$(id -u):$(id -g)" \
        --tmpfs /tmp:mode=1777 \
        -v "$PROJECT_ROOT/src/utest.sh:/usr/bin/utest:ro" \
        -v "$PROJECT_ROOT/src/utest.uc:/usr/share/ucode/utest.uc:ro" \
        -v "$PROJECT_ROOT/src/utest:/usr/share/ucode/utest:ro" \
        -v "$PROJECT_ROOT:/app" -w /app \
        "$IMAGE_OPENWRT" \
        utest -r detailed -c test/nocolor.config.uc \
            BundleX:examples/multi/01_bundle_a_test.uc BundleY:examples/multi/01_bundle_a_test.uc 2>&1)
    ok=1
    for bundle in BundleX BundleY; do
        n=$(printf '%s\n' "$out" | grep -cF "[$bundle] examples/multi/01_bundle_a_test.uc")
        [ "$n" -eq 1 ] || { echo "  [FAIL] dup-file-across-bundles ($bundle header appears $n times, expected 1)"; ok=0; }
    done
    printf '%s\n' "$out" | grep -q "Suites:  2" \
        || { echo "  [FAIL] dup-file-across-bundles (suite count did not count both occurrences)"; ok=0; }
    [ "$ok" -eq 1 ] && echo "  [PASS] dup-file-across-bundles (same file in two bundles gets two headers, two suite buckets)"
    return $(( ! ok ))
}
check_dup_file_across_bundles || failed_tests="$failed_tests dup_file_across_bundles"

if [ -z "$failed_tests" ]; then
    printf '\nSUCCESS: All features verified.\n'
    exit 0
else
    printf '\nFAILURE: Regressions found in:%s\n' "$failed_tests"
    exit 1
fi
