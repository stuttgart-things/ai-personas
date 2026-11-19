# runner

The container a persona runs in, and the script that starts it.

| File | Runs | Does |
| --- | --- | --- |
| `Containerfile` | build | image with only `claude`, `claims`, `curl`, `jq`, `js-yaml`, `ssh`; the build fails if `kubectl`, `gh`, `git` or `vault` is in it; user `persona` (uid 10001) |
| `entrypoint.sh` | in the container | prompt from scenario + persona rules, `claude -p` with the surface's settings and budget; the persona's only tool is `claims` (ADR 0001), plus `ssh` with a certificate for scenarios with `capabilities: [ssh]` (ADR 0003); writes `transcript.jsonl`, `transcript.md`, `friction.txt`, `summary.json`; deletes the output and fails if a token or the SSH key shows up in it |
| `run.sh` | host / CI | client credentials from Vault → short-lived token → `docker run` with only that token; for `ssh` scenarios a throwaway key signed by the lab's Vault SSH CA (30 min), mounted read-only |
| `publish-run`, `runs-index` | host / CI (`task publish`) | files a run's `transcript.md`, `transcript.jsonl`, `summary.json`, `friction.txt` in the private runs repo under `runs/<yyyy-mm>/<run-id>/` and regenerates its index (ADR 0005); `run.sh` calls it when the lab binding names `runsRepo` |
| `report` | in the container (`persona-report`) and `task report` | `transcript.jsonl` → `transcript.md`: header, command overview (start, duration, result), the order's phase timeline, commands with output, friction, denied calls, created orders (ADR 0002) |

## Tasks

`task` (Taskfile.yaml) wraps the commands below: `build` (Dagger), `build:docker`, `smoke` (image checks without an API key), `shell` (Dagger terminal in the persona's environment), `run`, `report`.

## Build

From the repository root:

```bash
docker build -f runner/Containerfile -t ai-personas-runner:local .

# or with Dagger (no local Docker daemon needed), exported to the local Docker:
dagger -c 'host | directory . | docker-build --dockerfile runner/Containerfile | export-image ai-personas-runner:local'
```

Versions are build args: `CLAUDE_CODE_VERSION`, `CLAIMS_VERSION`, `JS_YAML_VERSION`.

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

**Merge** (ADR 0004): `merge: human` (default) waits for a person to merge the order's pull request. `merge: auto` tells the persona it may order with `claims order --auto-merge`; machinery-order-service then merges once the checks pass, if a rule of the management cluster covers the persona's group (machinery-order-service ADR 0002). Without such a rule the order is refused, and the persona reports it. `verify-vm-ssh-auto` is the one-go variant of `verify-vm-ssh`.
