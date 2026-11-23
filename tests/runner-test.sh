#!/usr/bin/env bash
# Offline tests of the runner's scripts, no claude, no lab. Runs in the runner
# image (task smoke mounts tests/ at /tests) or on a host with bash, jq, node.
#   summary + report: a stream with several result events (#26)
#   cleanup: the persona's orders of this run against a fake claims (ADR 0007)
#   verdict: the scenario's verifiers against the run's orders (#4828)
# usage: tests/runner-test.sh [bin dir]   (default: runner/ next to tests/,
#        with the image's names persona-summary/-report/-cleanup when given)
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
bin=${1:-}
if [ -n "$bin" ]; then summary=$bin/persona-summary report=$bin/persona-report cleanup=$bin/persona-cleanup verdict=$bin/persona-verdict
else summary=$here/../runner/summary report=$here/../runner/report cleanup=$here/../runner/cleanup verdict=$here/../runner/verdict; fi
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

# --- summary and report over three segments ---------------------------------
run=$work/run; mkdir -p "$run"; cp "$here/fixtures/segments/transcript.jsonl" "$run/"
"$summary" "$run" r1 developer delete-vm-auto labul auto none
jq -e '.result | .num_turns == 8 and .total_cost_usd == 0.07 and .duration_ms == 64010 and .segments == 3
       and (.result | startswith("Ziel erreicht: ja")) and (.permission_denials | length) == 1' "$run/summary.json" >/dev/null \
  || fail "summary over segments: $(jq -c .result "$run/summary.json")"
jq -e '.cleanup == {mode: "none", orders: null}' "$run/summary.json" >/dev/null || fail "summary cleanup"
node "$report" "$run" >/dev/null
md=$run/transcript.md
grep -q '^| Turns | 8 (3 Abschnitte) |$' "$md" || fail "report turns: $(grep Turns "$md")"
grep -q '^| Kosten | 0.07 USD |$' "$md" || fail "report cost"
for p in Ordered PROpen Merged Ready TeardownPROpen TearingDown Deleted; do
  grep -qE "^\| [0-9:]{8} \| $p \|" "$md" || fail "report timeline lacks $p"
done
grep -q 'Von Ordered bis Deleted: 19:55 min.' "$md" || fail "report timeline span"
grep -q 'cleanup: none' "$md" || fail "report cleanup none"
echo "summary + report over segments ok"

# --- cleanup ----------------------------------------------------------------
export FAKE_DIR=$work/fake; mkdir -p "$FAKE_DIR/orders" "$work/bin"
ln -s "$here/fake-claims" "$work/bin/claims"
now=$(date -u +%s); at() { date -u -d "@$(( now + $1 ))" +%Y-%m-%dT%H:%M:%SZ; }
order() { # id created phase auto [refuseAutoTeardown]
  jq -n --arg id "$1" --arg c "$2" --arg p "$3" --argjson auto "$4" --argjson refuse "${5:-false}" \
    '{metadata: {name: $id, creationTimestamp: $c}, spec: (if $auto then {autoMerge: {rule: "r"}} else {} end),
      status: {phase: $p}, fake: {refuseAutoTeardown: $refuse}}' > "$FAKE_DIR/orders/$1.json"
}
order ord-old000000000 "$(at -7200)" Ready true          # an earlier run: untouched
order ord-ready0000000 "$(at 30)"    Ready true          # teardown --auto-merge -> Deleted
order ord-propen000000 "$(at 40)"    PROpen true         # cancel
order ord-human0000000 "$(at 50)"    Ready false         # teardown, a human merges
order ord-norule000000 "$(at 60)"    Building true true  # rule refuses teardowns -> human
order ord-gone00000000 "$(at 70)"    Deleted true        # persona deleted it itself
crun=$work/crun; mkdir -p "$crun"
rc=0; PATH=$work/bin:$PATH RUN_ID=r2 "$cleanup" "$crun" "$(at 0)" 2>"$work/cleanup.log" || rc=$?
[ $rc -eq 1 ] || fail "cleanup exit $rc, want 1 (two teardowns wait for a human)"
c=$crun/cleanup.json
want='{"ord-ready0000000":"deleted","ord-propen000000":"cancelled","ord-human0000000":"waiting-for-merge","ord-norule000000":"waiting-for-merge","ord-gone00000000":"nothing"}'
got=$(jq -c 'map({(.order): .outcome}) | add' "$c")
jq -e --argjson w "$want" --argjson g "$got" -n '$w == $g' >/dev/null || fail "cleanup outcomes: $got"
grep -q '^orders teardown ord-ready0000000 .*--auto-merge' "$FAKE_DIR/calls" || fail "auto-merged order not torn down with --auto-merge"
grep -E '^orders teardown ord-human0000000 ' "$FAKE_DIR/calls" | grep -q -- --auto-merge && fail "human order torn down with --auto-merge"
grep -q 'ord-old000000000' "$FAKE_DIR/calls" && fail "order of an earlier run touched"
jq -e '.[] | select(.order == "ord-human0000000") | .pr == "https://github.com/o/fleet/pull/9" and .from == "Ready"' "$c" >/dev/null \
  || fail "waiting-for-merge without the pull request"
grep -q 'cleanup after persona run r2' "$FAKE_DIR/calls" || fail "teardown reason"
echo "cleanup ok"

# --- report with cleanup ----------------------------------------------------
cp "$here/fixtures/segments/transcript.jsonl" "$crun/"
"$summary" "$crun" r2 developer delete-vm-auto labul auto delete-claim
node "$report" "$crun" >/dev/null
grep -q '^| `ord-human0000000` | Ready | teardown | waiting-for-merge | https://github.com/o/fleet/pull/9 |' "$crun/transcript.md" \
  || fail "report cleanup table: $(sed -n '/Aufräumen/,/^---/p' "$crun/transcript.md")"
echo "report with cleanup ok"

# --- report timeline from mixed and cut JSON output ---------------------------
mix=$work/mix; mkdir -p "$mix"
node -e '
const h = (m, p, t) => `      {\n        "message": "${m}",\n        "phase": "${p}",\n        "time": "2026-11-22T${t}Z"\n      }`;
const full = `Sun Nov 22 10:00:00 UTC 2026\n{\n  "status": {\n    "history": [\n${[h("accepted","Ordered","10:00:01"), h("x is Ready","Ready","10:09:00")].join(",\n")}\n    ]\n  }\n}`;
const cut = `        "time": "2026-11-22T10:10:00Z"\n      },\n${h("teardown merged","TearingDown","10:12:00")},\n${h("torn down","Deleted","10:20:00")}\n    ],\n    "live": {`;
const ev = [];
[["a", "date; claims order t --wait -o json", full], ["b", "claims orders teardown ord-x -o json | tail -60", cut]].forEach(([id, cmd, out]) => {
  ev.push({ type: "assistant", timestamp: "2026-11-22T10:00:00Z", message: { content: [{ type: "tool_use", id, name: "Bash", input: { command: cmd } }] } });
  ev.push({ type: "user", timestamp: "2026-11-22T10:00:00Z", message: { content: [{ type: "tool_result", tool_use_id: id, content: out }] } });
});
ev.push({ type: "result", subtype: "success", num_turns: 2, total_cost_usd: 0.01, duration_ms: 1000, result: "ok" });
process.stdout.write(ev.map((e) => JSON.stringify(e)).join("\n") + "\n");' > "$mix/transcript.jsonl"
node "$report" "$mix" >/dev/null
for p in Ordered Ready TearingDown Deleted; do
  grep -qE "^\| [0-9:]{8} \| $p \|" "$mix/transcript.md" || fail "timeline from mixed/cut output lacks $p"
done
echo "report timeline from mixed and cut output ok"

# --- verdict ----------------------------------------------------------------
# A passing verify-vm-ssh-auto run on machinery-dev, then the same run with the
# order on the wrong cluster and without Ready.
vrun=$work/vrun; mkdir -p "$vrun"; rm -f "$FAKE_DIR"/orders/*.json
printf '%s\n' '{"type":"result","subtype":"success","is_error":false,"result":"ok"}' > "$vrun/transcript.jsonl"
echo '[{"order":"ord-v1","outcome":"deleted"}]' > "$vrun/cleanup.json"
vorder() { # id cluster history-json
  jq -n --arg id "$1" --arg c "$(at 30)" --arg mc "$2" --argjson h "$3" \
    '{metadata: {name: $id, creationTimestamp: $c},
      spec: {autoMerge: {rule: "persona-test-vms"}, placement: {managementCluster: $mc}, parameters: {owner: "group:default/ai-personas"}},
      status: {phase: "Deleted", history: $h,
               delivery: {pullRequest: {url: "https://github.com/o/fleet/pull/1", state: "merged"}}}}' > "$FAKE_DIR/orders/$1.json"
}
vorder ord-v1 machinery-dev '[{"phase":"Ordered"},{"phase":"PROpen"},{"phase":"Merged"},{"phase":"Ready"},{"phase":"Deleted"}]'
scen=$here/../scenarios/verify-vm-ssh-auto.yaml
PATH=$work/bin:$PATH MANAGEMENT_CLUSTER=machinery-dev "$verdict" "$vrun" "$scen" "$(at 0)" >/dev/null
jq -e '.passed and .orders == 1 and .managementCluster == "machinery-dev"
       and ([.checks[] | select(.kind == "hard") | .name] | sort) == ["auto-merged","claude-finished","cleanup","cluster","order-pr","xr-ready"]
       and ([.checks[] | select(.name == "ssh-login")][0].kind == "advisory")' "$vrun/verdict.json" >/dev/null \
  || fail "verdict pass: $(jq -c . "$vrun/verdict.json")"
vorder ord-v1 machinery-labul '[{"phase":"Ordered"},{"phase":"Merged"},{"phase":"Deleted"}]'
PATH=$work/bin:$PATH MANAGEMENT_CLUSTER=machinery-dev "$verdict" "$vrun" "$scen" "$(at 0)" >/dev/null
jq -e '(.passed | not) and ([.checks[] | select(.ok == false) | .name] | sort) == ["cluster","xr-ready"]' "$vrun/verdict.json" >/dev/null \
  || fail "verdict fail: $(jq -c '[.checks[] | {name, ok}]' "$vrun/verdict.json")"
"$summary" "$vrun" r3 developer verify-vm-ssh-auto labul auto delete-claim
jq -e '.verdict.passed == false' "$vrun/summary.json" >/dev/null || fail "summary verdict"
echo "verdict ok"
