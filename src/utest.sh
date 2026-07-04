#!/bin/sh

UTEST_SRC=/usr/share/ucode
UTEST_RUN_DIR=$(mktemp -d /tmp/utest_XXXXXX)
cleanup() { rm -rf "$UTEST_RUN_DIR"; }
# Trap the fatal signals too, not just EXIT: busybox ash does not run the EXIT
# trap when killed by an untrapped signal, so a ^C (INT) or a kill (TERM/HUP)
# would otherwise leave the run dir (shims + worker output files) behind. Safe
# under -jN: the shell waits for the foreground ucode, which survives ^C via
# uloop and prints the summary, before this trap fires.
trap cleanup EXIT INT TERM HUP

usage() {
    cat <<'EOF'
utest — A modern, non-invasive testing stack for the ucode ecosystem.

Usage:
  utest [options] [<bundle>...]

Options:
  -h          Show this screen.
  -r <fmt>    Reporter format: detailed, compact, json  [default: detailed].
  -f <regex>  Only run tests whose name matches regex.
  -c <path>   Config file  [default: utest.config.uc].
  -l <path>   Add a library search path (repeatable).
  -j <n>      Number of parallel workers.
  -s <seed>   Random seed for property-based tests.

Examples:
  utest test/unit
  utest -r json test/unit
  utest -f auth -c ci.config.uc
EOF
    exit 0
}

json_str() { printf '"%s"' "$(printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g')"; }
json_opt() { [ -n "$1" ] && json_str "$1" || printf 'null'; }

reporter="" filter="" config="" lib_paths_json="" jobs="" seed=""

while getopts ":hr:f:c:l:j:s:" opt; do
    case $opt in
        h) usage ;;
        r) reporter=$OPTARG ;;
        f) filter=$OPTARG ;;
        c) config=$OPTARG ;;
        l) lib_paths_json="${lib_paths_json:+$lib_paths_json,}$(json_str "$OPTARG")" ;;
        j) jobs=$OPTARG ;;
        s) seed=$OPTARG ;;
        :) printf 'Option -%s requires an argument.\n' "$OPTARG" >&2; exit 1 ;;
       \?) printf 'Unknown option: -%s\n' "$OPTARG" >&2; exit 1 ;;
    esac
done
shift $((OPTIND - 1))

opts=$(printf '{"reporter":%s,"filter":%s,"config":%s,"run_dir":%s,"src_dir":%s,"lib_paths":[%s],"jobs":%s,"seed":%s}' \
    "$(json_opt "$reporter")" \
    "$(json_opt "$filter")" \
    "$(json_opt "$config")" \
    "$(json_str "$UTEST_RUN_DIR")" \
    "$(json_str "$UTEST_SRC")" \
    "$lib_paths_json" \
    "$(json_opt "$jobs")" \
    "$(json_opt "$seed")")

ucode -L "$UTEST_SRC" -L "$UTEST_SRC/utest/runner" -L "$UTEST_SRC/utest/runner/worker" \
    "$UTEST_SRC/utest/cli.uc" -- "$opts" "$@"
