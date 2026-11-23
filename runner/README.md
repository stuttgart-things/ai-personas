# runner

The container a persona runs in, and the script that starts it.

| File | Runs | Does |
| --- | --- | --- |
| `Containerfile` | build | image with only `claude`, `claims`, `curl`, `jq`, `js-yaml`, `ssh`; the build fails if `kubectl`, `gh`, `git` or `vault` is in it; user `persona` (uid 10001) |
| `entrypoint.sh` | in the container | prompt from scenario + persona rules, `claude -p` with the surface's settings and budget; the persona's only tool is `claims` (ADR 0001), plus `ssh` with a certificate for scenarios with `capabilities: [ssh]` (ADR 0003); afterwards `persona-cleanup` for `cleanup: delete-claim` (ADR 0007); writes `transcript.jsonl`, `transcript.md`, `friction.txt`, `summary.json`, `cleanup.json`; deletes the output and fails if a token or the SSH key shows up in it |
| `run.sh` | host / CI | client credentials from Vault → short-lived token → `docker run` with only that token; for `ssh` scenarios a throwaway key signed by the lab's Vault SSH CA (30 min), mounted read-only |
| `publish-run`, `runs-index` | host / CI (`task publish`) | files a run's `transcript.md`, `transcript.jsonl`, `summary.json`, `friction.txt` in the private runs repo under `runs/<scenario>/<yyyy-mm-ddThh-mm>-<persona>/` and regenerates the indexes (all runs, and one per scenario) (ADR 0005); `run.sh` calls it when the lab binding names `runsRepo` |
| `cleanup` | in the container (`persona-cleanup`) | the persona's orders of this run: cancel before the merge, `claims orders teardown` after it (`--auto-merge` where the order was auto-merged), waits for Deleted/Cancelled up to `CLEANUP_TIMEOUT` (45m); writes `cleanup.json` (ADR 0007) |
| `verdict` | in the container (`persona-verdict`), after `cleanup` | did the scenario pass? Checks the scenario's `expect:` verifiers that the order data proves (`order-pr`, `auto-merged`, `xr-ready`, `teardown-pr`, `xr-deleted`, `order-refused`) plus `claude-finished`, `cleanup` and, with `MANAGEMENT_CLUSTER`, `cluster`; the rest (`ssh-login`, `order-owner`, ...) is advisory. Writes `verdict.json` (`passed`, `checks[]`), folded into `summary.json`; always exits 0 -- the caller decides (stage-time `verifyStrict`) |
| `summary` | in the container (`persona-summary`) | `summary.json` over all `result` events: a run with background tasks has one per segment; cost is cumulative (max), turns and duration per segment (sum) |
| `report` | in the container (`persona-report`) and `task report` | `transcript.jsonl` → `transcript.md`: header, command overview (start, duration, result), the order's phase timeline, commands with output, friction, denied calls, created orders, cleanup (ADR 0002) |

## Tasks

`task` (Taskfile.yaml) wraps the commands below: `build` (Dagger), `build:docker`, `smoke` (image checks without an API key, includes `tests/runner-test.sh` in the image), `test` (`tests/runner-test.sh` on the host: summary over several segments, cleanup against a fake `claims`), `shell` (Dagger terminal in the persona's environment), `run`, `report`.

## Build

From the repository root:

```bash
docker build -f runner/Containerfile -t ai-personas-runner:local .

# or with Dagger (no local Docker daemon needed), exported to the local Docker:
dagger -c 'host | directory . | docker-build --dockerfile runner/Containerfile | export-image ai-personas-runner:local'
```

Versions are build args: `CLAUDE_CODE_VERSION`, `CLAIMS_VERSION`, `JS_YAML_VERSION`.

**Published image:** `ghcr.io/stuttgart-things/ai-personas-runner`, built by `.github/workflows/runner-image.yaml` with the stuttgart-things Dagger docker module from this Containerfile. Pull requests build to ttl.sh and run `task smoke` and Trivy; main publishes `:<commit sha>` and `:latest`. Pin the commit sha: the Tekton pipeline (stage-time `execute-persona-run`) takes it as `runnerImage`, and the same sha as `aiPersonasRevision` for `publish-run`.

## Run

The lab binding (endpoints, Vault, CA) lives in the private fleet repo; this repo names no hosts.

```bash
export LAB_FILE=<fleet repo>/ai-personas/labul.yaml   # lab, claimApiUrl, orderApiUrl, caFile, sshCaMount
export VAULT_ADDR=... VAULT_TOKEN=...                 # read on ai-personas/<lab>/*, sign on <sshCaMount>/sign/persona-*
export CLAUDE_CODE_OAUTH_TOKEN=...                    # claude setup-token (subscription), or ANTHROPIC_API_KEY
task run PERSONA=developer SCENARIO=order-baseos-vm
ls runs/<run-id>/                                     # transcript.md transcript.jsonl friction.txt summary.json
```

**Subscription instead of an API key** (`claude setup-token`): fine for local test runs; the token belongs to one person's account and its usage limits, so it stays out of shared CI. Regular CI runs use an API key.

The lab's root CA (`caFile`) is mounted at `/etc/ssl/extra/ca.pem` and added to the system roots for `claims`, `curl` and `claude`.

Transcripts contain API answers and hostnames: keep them out of this public repo (`runs/` is ignored). They go to the private runs repo the lab binding names (`runsRepo`, ADR 0005), pushed by `run.sh` with the host's git credentials after the leak check passed.

**SSH** (ADR 0003): a scenario with `capabilities: [ssh]` gets a throwaway key that the lab's Vault SSH CA signs for 30 minutes (role `persona-<persona>`, login `sthings`). VMs trust that CA when `sthings.baseos.setup` built them. The certificate's clock starts with the run, so a scenario that orders a VM and then logs in needs the merge within that time.

**Management cluster:** where a lab has several (LabUL: `machinery-labul` and the staging cluster `machinery-dev`, stuttgart-things/stuttgart-things#4828), `MANAGEMENT_CLUSTER` tells the persona which one to order on (`claims order … --cluster`), and the verdict fails a run whose order landed elsewhere. Unset, the persona picks from `claims clusters` as before.

**Merge** (ADR 0004): `merge: human` (default) waits for a person to merge the order's pull request. `merge: auto` tells the persona it may order with `claims order --auto-merge`; machinery-order-service then merges once the checks pass, if a rule of the management cluster covers the persona's group (machinery-order-service ADR 0002). Without such a rule the order is refused, and the persona reports it. `verify-vm-ssh-auto` is the one-go variant of `verify-vm-ssh`.

**Cleanup** (ADR 0007): `cleanup: delete-claim` (most scenarios) makes the runner remove what the persona ordered in this run, after claude and also when claude failed: cancel before the merge, teardown after it, through machinery-order-service only. `cleanup: none` keeps it. `delete-vm-auto` lets the persona delete its VM itself; the runner's cleanup is the safety net there.
