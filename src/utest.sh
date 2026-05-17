#!/bin/sh

# This script is located in the src/ directory
UTEST_SRC=$(cd "$(dirname "$0")" && pwd)

# Create the run_dir here so the EXIT trap can clean it up on Ctrl+C or crash.
# NOTE: We do NOT include the shims directory here, as the coordinator
# needs the real 'fs' module for discovery.
UTEST_RUN_DIR=$(mktemp -d /tmp/utest_XXXXXX)
cleanup() { rm -rf "$UTEST_RUN_DIR"; }
trap cleanup EXIT

ucode -L "$UTEST_SRC" -L "$UTEST_SRC/utest/runner" -L "$UTEST_SRC/utest/runner/worker" \
    "$UTEST_SRC/utest/cli.uc" -- --run-dir="$UTEST_RUN_DIR" --src-dir="$UTEST_SRC" "$@"
