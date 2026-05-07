#!/bin/bash
set -e

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
CLIENT_SCRIPT="$SCRIPT_DIR/vrs-client.sh"
EXAMPLE_JSON="$REPO_ROOT/docs/ai-contract/vless-reality.example.json"
TEST_HOME="/private/tmp/vrs-client-regression-$$"
ALPHA_OUT="/private/tmp/vrs-client-test-alpha-$$.out"
BETA_OUT="/private/tmp/vrs-client-test-beta-$$.out"

cleanup() {
    rm -rf "$TEST_HOME"
    rm -f "$ALPHA_OUT" "$BETA_OUT"
}

trap cleanup EXIT

log() {
    echo "[TEST] $1"
}

fail() {
    echo "[FAIL] $1" >&2
    exit 1
}

run_client() {
    VRS_CLIENT_HOME="$TEST_HOME" bash "$CLIENT_SCRIPT" "$@"
}

assert_fails() {
    if run_client "$@"; then
        fail "expected command to fail: $*"
    fi
}

assert_node() {
    node -e "$1" "$TEST_HOME"
}

if ! command -v node >/dev/null 2>&1; then
    fail "node is required for JSON assertions"
fi

log "syntax check"
bash -n "$CLIENT_SCRIPT"

log "import two profiles"
run_client import "$EXAMPLE_JSON" --name alpha --priority 10 >"$ALPHA_OUT"
run_client import "$EXAMPLE_JSON" --name beta --priority 20 >"$BETA_OUT"

log "validate index and generated xray config"
assert_node '
const fs = require("fs");
const home = process.argv[1];
const index = JSON.parse(fs.readFileSync(`${home}/profiles/index.json`, "utf8"));
if (index.schemaVersion !== "vrs.client.profiles.v1") throw new Error("bad index schema");
if (index.current !== "alpha") throw new Error(`expected current alpha, got ${index.current}`);
if (!index.profiles.alpha || !index.profiles.beta) throw new Error("missing profiles");
if (index.profiles.alpha.priority !== 10) throw new Error("bad alpha priority");
if (index.profiles.beta.priority !== 20) throw new Error("bad beta priority");
const config = JSON.parse(fs.readFileSync(`${home}/xray/alpha.config.json`, "utf8"));
if (config.inbounds[0].protocol !== "socks") throw new Error("missing socks inbound");
if (config.inbounds[1].protocol !== "http") throw new Error("missing http inbound");
if (config.outbounds[0].protocol !== "vless") throw new Error("missing vless outbound");
if (config.outbounds[0].streamSettings.security !== "reality") throw new Error("missing reality security");
'

log "validate list output"
sorted_output=$(run_client list --sorted)
echo "$sorted_output" | grep -q "alpha" || fail "list --sorted missing alpha"
echo "$sorted_output" | grep -q "beta" || fail "list --sorted missing beta"

log "check failure writes offline status"
assert_fails check --name beta
assert_node '
const fs = require("fs");
const home = process.argv[1];
const index = JSON.parse(fs.readFileSync(`${home}/profiles/index.json`, "utf8"));
if (index.profiles.beta.lastStatus !== "offline") throw new Error("beta should be offline");
if (index.profiles.beta.failureCount !== 1) throw new Error(`beta failureCount should be 1, got ${index.profiles.beta.failureCount}`);
'

log "auto-use failure tries all candidates"
assert_fails auto-use
assert_node '
const fs = require("fs");
const home = process.argv[1];
const index = JSON.parse(fs.readFileSync(`${home}/profiles/index.json`, "utf8"));
if (index.current !== "beta") throw new Error(`expected current beta after auto-use, got ${index.current}`);
if (index.profiles.alpha.lastStatus !== "offline") throw new Error("alpha should be offline");
if (index.profiles.beta.lastStatus !== "offline") throw new Error("beta should be offline");
if (index.profiles.alpha.failureCount < 1) throw new Error("alpha failureCount not incremented");
if (index.profiles.beta.failureCount < 2) throw new Error("beta failureCount not incremented by auto-use");
'

log "watch once failure falls back to auto-use"
assert_fails watch --once --interval 5
assert_node '
const fs = require("fs");
const home = process.argv[1];
const index = JSON.parse(fs.readFileSync(`${home}/profiles/index.json`, "utf8"));
if (!["alpha", "beta"].includes(index.current)) throw new Error("current should remain a known profile");
if (index.profiles.alpha.lastStatus !== "offline") throw new Error("alpha should remain offline");
if (index.profiles.beta.lastStatus !== "offline") throw new Error("beta should remain offline");
'

log "invalid interval and missing subcommands fail"
assert_fails watch --interval 1 --once
assert_fails service
assert_fails watch-service

log "config prints watcher log path"
config_output=$(run_client config)
echo "$config_output" | grep -q "Watcher log:" || fail "config missing watcher log path"

log "done"
