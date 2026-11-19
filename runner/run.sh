#!/usr/bin/env bash
# Host / CI side of a run: credentials from Vault -> short-lived token ->
# runner container with only that token. Prints no secret.
# usage: runner/run.sh <persona> <scenario>
#
# Lab binding, either LAB_FILE (YAML in the private fleet repo, read with yq):
#   lab: labul
#   claimApiUrl: https://...
#   orderApiUrl: https://...
#   caFile: path/to/root-ca.pem   # relative to the fleet repo root
#   sshCaMount: ssh-client-signer # Vault SSH CA (ADR 0003), role persona-<persona>
#   runsRepo: owner/repo          # private repo the reports go to (ADR 0005)
# or the same as environment: LAB, CLAIM_API_URL, ORDER_API_URL, CA_FILE,
# SSH_CA_MOUNT, RUNS_REPO. Without a runs repo the report stays in OUT_DIR.
#
# Credentials (environment, never in a file here):
#   VAULT_ADDR, VAULT_TOKEN  read access to ai-personas/<lab>/<persona>; for
#                            scenarios with capabilities: [ssh] also update on
#                            <sshCaMount>/sign/persona-<persona>
#   CLAUDE_CODE_OAUTH_TOKEN  (claude setup-token, subscription) or ANTHROPIC_API_KEY
# Optional: IMAGE (default ai-personas-runner:local), OUT_DIR (default ./runs)
set -euo pipefail
persona=${1:?persona}; scenario=${2:?scenario}

if [ -n "${LAB_FILE:-}" ]; then
  root=$(git -C "$(dirname "$LAB_FILE")" rev-parse --show-toplevel)
  LAB=$(yq -r .lab "$LAB_FILE")
  CLAIM_API_URL=$(yq -r .claimApiUrl "$LAB_FILE")
  ORDER_API_URL=$(yq -r .orderApiUrl "$LAB_FILE")
  ca=$(yq -r '.caFile // ""' "$LAB_FILE"); [ -n "$ca" ] && CA_FILE=$root/$ca
  SSH_CA_MOUNT=$(yq -r '.sshCaMount // ""' "$LAB_FILE")
  RUNS_REPO=${RUNS_REPO:-$(yq -r '.runsRepo // ""' "$LAB_FILE")}
fi
: "${LAB:?LAB}" "${CLAIM_API_URL:?CLAIM_API_URL}" "${ORDER_API_URL:?ORDER_API_URL}"
[ -n "${CLAUDE_CODE_OAUTH_TOKEN:-}${ANTHROPIC_API_KEY:-}" ] \
  || { echo "CLAUDE_CODE_OAUTH_TOKEN or ANTHROPIC_API_KEY missing" >&2; exit 1; }
export LAB CLAIM_API_URL
export CLAIM_ORDERS_URL=$ORDER_API_URL
image=${IMAGE:-ai-personas-runner:local}
out=${OUT_DIR:-$PWD/runs}; mkdir -p "$out"
export RUN_ID=${RUN_ID:-$(date -u +%Y-%m-%dT%H-%M)-$persona-$scenario}

cacurl=(); camount=()
if [ -n "${CA_FILE:-}" ]; then
  cacurl=(--cacert "$CA_FILE"); camount=(-v "$CA_FILE:/etc/ssl/extra/ca.pem:ro")
fi

creds=$(vault kv get -format=json "ai-personas/$LAB/$persona" | jq -c .data.data)
token=$(curl -fsS "${cacurl[@]}" "$(jq -r .token_url <<<"$creds")" \
  --data-urlencode grant_type=client_credentials \
  --data-urlencode "client_id=$(jq -r .client_id <<<"$creds")" \
  --data-urlencode "client_secret=$(jq -r .client_secret <<<"$creds")" \
  --data-urlencode "scope=$(jq -r .scope <<<"$creds")" | jq -r '.access_token // empty')
unset creds
[ -n "$token" ] || { echo "no token for persona $persona" >&2; exit 1; }

# SSH (ADR 0003): a throwaway key, signed for 30 minutes by the lab's Vault
# SSH CA, mounted read-only; removed when the run ends. Only for scenarios
# that ask for it.
sshmount=()
here=$(cd "$(dirname "$0")/.." && pwd)
if yq -e '(.capabilities // []) | contains(["ssh"])' "$here/scenarios/$scenario.yaml" >/dev/null 2>&1; then
  sshdir=$(mktemp -d); trap 'rm -rf "$sshdir"' EXIT
  ssh-keygen -q -t ed25519 -N "" -C "persona-$persona@$LAB" -f "$sshdir/id_ed25519"
  vault write -field=signed_key "${SSH_CA_MOUNT:-ssh-client-signer}/sign/persona-$persona" \
    public_key=@"$sshdir/id_ed25519.pub" valid_principals=sthings > "$sshdir/id_ed25519-cert.pub"
  chmod 644 "$sshdir/id_ed25519" "$sshdir/id_ed25519-cert.pub"   # read by the container's uid (= ours)
  echo "ssh: $(ssh-keygen -L -f "$sshdir/id_ed25519-cert.pub" | sed -n 's/^ *Valid: //p')"
  sshmount=(-v "$sshdir:/run/persona-ssh:ro")
fi

# Values go in by name only (-e VAR), so they never appear in ps or logs.
# The container runs as the caller's uid so it can write the mounted output
# directory; HOME is a writable path in the container for claude's state.
envs=(--user "$(id -u):$(id -g)" -e HOME=/tmp/persona-home -e PERSONA_TOKEN -e CLAIM_API_URL -e CLAIM_ORDERS_URL -e LAB -e RUN_ID)
[ -n "${CLAUDE_CODE_OAUTH_TOKEN:-}" ] && envs+=(-e CLAUDE_CODE_OAUTH_TOKEN)
[ -n "${ANTHROPIC_API_KEY:-}" ] && envs+=(-e ANTHROPIC_API_KEY)
PERSONA_TOKEN=$token docker run --rm "${envs[@]}" "${camount[@]}" "${sshmount[@]}" \
  -v "$out:/out" "$image" "$persona" "$scenario"

# The report into the private runs repo (ADR 0005), with the host's git
# credentials. Only reached when the run passed its leak check (the
# container fails otherwise). A failed push keeps the local copy.
if [ -n "${RUNS_REPO:-}" ]; then
  "$here/runner/publish-run" "$out/$RUN_ID" "$RUNS_REPO" || echo "report not published, kept in $out/$RUN_ID" >&2
fi
