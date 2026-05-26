#!/bin/sh

# Find the absolute path of the project root
PROJECT_ROOT=$(cd "$(dirname "$0")/.." && pwd)

# Execute the verification harness inside the Docker environment
run_verify() {
    example=$1
    expected=$2
    extra_flags=${3:-""}
    docker run --rm \
        -v "$PROJECT_ROOT/src/utest.sh:/usr/bin/utest:ro" \
        -v "$PROJECT_ROOT/src/utest.uc:/usr/share/ucode/utest.uc:ro" \
        -v "$PROJECT_ROOT/src/utest:/usr/share/ucode/utest:ro" \
        -v "$PROJECT_ROOT:/app" \
        -w /app \
        openwrt/rootfs:x86-64-openwrt-24.10 \
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

if [ -z "$failed_tests" ]; then
    printf '\nSUCCESS: All features verified.\n'
    exit 0
else
    printf '\nFAILURE: Regressions found in:%s\n' "$failed_tests"
    exit 1
fi
