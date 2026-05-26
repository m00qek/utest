#!/bin/sh

UTEST_SRC=/usr/share/ucode
UTEST_RUN_DIR=$(mktemp -d /tmp/utest_XXXXXX)
cleanup() { rm -rf "$UTEST_RUN_DIR"; }
trap cleanup EXIT

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

Examples:
  utest test/unit
  utest -r json test/unit
  utest -f auth -c ci.config.uc
EOF
    exit 0
}

json_str() { printf '"%s"' "$(printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g')"; }
json_opt() { [ -n "$1" ] && json_str "$1" || printf 'null'; }

reporter="" filter="" config="" lib_paths_json=""

while getopts ":hr:f:c:l:" opt; do
    case $opt in
        h) usage ;;
        r) reporter=$OPTARG ;;
        f) filter=$OPTARG ;;
        c) config=$OPTARG ;;
        l) lib_paths_json="${lib_paths_json:+$lib_paths_json,}$(json_str "$OPTARG")" ;;
        :) printf 'Option -%s requires an argument.\n' "$OPTARG" >&2; exit 1 ;;
       \?) printf 'Unknown option: -%s\n' "$OPTARG" >&2; exit 1 ;;
    esac
done
shift $((OPTIND - 1))

opts=$(printf '{"reporter":%s,"filter":%s,"config":%s,"run_dir":%s,"src_dir":%s,"lib_paths":[%s]}' \
    "$(json_opt "$reporter")" \
    "$(json_opt "$filter")" \
    "$(json_opt "$config")" \
    "$(json_str "$UTEST_RUN_DIR")" \
    "$(json_str "$UTEST_SRC")" \
    "$lib_paths_json")

ucode -L "$UTEST_SRC" -L "$UTEST_SRC/utest/runner" -L "$UTEST_SRC/utest/runner/worker" \
    "$UTEST_SRC/utest/cli.uc" -- "$opts" "$@"
