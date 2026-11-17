# runner

The container a persona runs in, and the script that starts it.

| File | Runs | Does |
| --- | --- | --- |
| `Containerfile` | build | image with only `claude`, `claims`, `curl`, `jq`, `js-yaml`; the build fails if `kubectl`, `gh`, `git`, `vault` or `ssh` is in it; user `persona` (uid 10001) |
| `entrypoint.sh` | in the container | prompt from scenario + persona rules, `claude -p` with the surface's settings and budget; writes `transcript.jsonl`, `friction.txt`, `summary.json`; deletes the output and fails if the token shows up in it |
| `run.sh` | host / CI | client credentials from Vault → short-lived token → `docker run` with only that token |

## Tasks

`task` (Taskfile.yaml) wraps the commands below: `build` (Dagger), `build:docker`, `smoke` (image checks without an API key), `shell` (Dagger terminal in the persona's environment), `run`.

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
export LAB_FILE=<fleet repo>/ai-personas/labul.yaml   # lab, claimApiUrl, orderApiUrl, caFile
export VAULT_ADDR=... VAULT_TOKEN=...                 # read on ai-personas/<lab>/*
export CLAUDE_CODE_OAUTH_TOKEN=...                    # claude setup-token (subscription), or ANTHROPIC_API_KEY
task run PERSONA=developer SCENARIO=order-baseos-vm
ls runs/<run-id>/                                     # transcript.jsonl friction.txt summary.json
```

**Subscription instead of an API key** (`claude setup-token`): fine for local test runs; the token belongs to one person's account and its usage limits, so it stays out of shared CI. Regular CI runs use an API key.

The lab's root CA (`caFile`) is mounted at `/etc/ssl/extra/ca.pem` and added to the system roots for `claims`, `curl` and `claude`.

Transcripts contain API answers and hostnames: keep them out of this public repo (`runs/` is ignored).
