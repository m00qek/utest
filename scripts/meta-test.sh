#!/bin/sh

# Find the absolute path of the project root
PROJECT_ROOT=$(cd "$(dirname "$0")/.." && pwd)

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
    # Map the host uid/gid so any files the run touches under the bind-mounted
    # repo are host-owned, not root. --tmpfs gives a writable /tmp for utest.sh's
    # mktemp run dir (newer rootfs images ship /tmp as 0755 root-owned).
    docker run --rm \
        --user "$(id -u):$(id -g)" \
        --tmpfs /tmp:mode=1777 \
        -v "$PROJECT_ROOT/src/utest.sh:/usr/bin/utest:ro" \
        -v "$PROJECT_ROOT/src/utest.uc:/usr/share/ucode/utest.uc:ro" \
        -v "$PROJECT_ROOT/src/utest:/usr/share/ucode/utest:ro" \
        -v "$PROJECT_ROOT:/app" \
        -w /app \
        "$IMAGE_OPENWRT" \
        ucode test/verify.uc "$example" "$expected" "$extra_flags"
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
        echo "  [SKIP] $f (No baseline)"
        continue
    fi

    # Pass custom bundle name for the bundle test
    bundle_arg="$f"
    if [ "$rel_path" = "unit/08_bundles_test.uc" ]; then
        bundle_arg="MyBundle:$f"
    fi

    # Detect companion config file (e.g. 09_config.uc alongside 09_standard_shim_test.uc)
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
# The two files have no individual baselines so the main loop skips them.
timeout_arg="Pass:examples/timeout/01_pass_test.uc Hang:examples/timeout/02_hang_test.uc"
if run_verify "$timeout_arg" "test/json/timeout/timeout_test.json" "-j 2 -c examples/timeout/timeout.config.uc"; then
    :
else
    failed_tests="$failed_tests timeout_test"
fi

if [ -z "$failed_tests" ]; then
    printf '\nSUCCESS: All features verified.\n'
    exit 0
else
    printf '\nFAILURE: Regressions found in:%s\n' "$failed_tests"
    exit 1
fi
