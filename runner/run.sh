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
# or the same as environment: LAB, CLAIM_API_URL, ORDER_API_URL, CA_FILE.
#
# Credentials (environment, never in a file here):
#   VAULT_ADDR, VAULT_TOKEN  read access to ai-personas/<lab>/<persona>
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
fi
: "${LAB:?LAB}" "${CLAIM_API_URL:?CLAIM_API_URL}" "${ORDER_API_URL:?ORDER_API_URL}"
[ -n "${CLAUDE_CODE_OAUTH_TOKEN:-}${ANTHROPIC_API_KEY:-}" ] \
  || { echo "CLAUDE_CODE_OAUTH_TOKEN or ANTHROPIC_API_KEY missing" >&2; exit 1; }
export CLAIM_API_URL ORDER_API_URL
image=${IMAGE:-ai-personas-runner:local}
out=${OUT_DIR:-$PWD/runs}; mkdir -p "$out"

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

# Values go in by name only (-e VAR), so they never appear in ps or logs.
# The container runs as the caller's uid so it can write the mounted output
# directory; HOME is a writable path in the container for claude's state.
envs=(--user "$(id -u):$(id -g)" -e HOME=/tmp/persona-home -e PERSONA_TOKEN -e CLAIM_API_URL -e ORDER_API_URL -e RUN_ID)
[ -n "${CLAUDE_CODE_OAUTH_TOKEN:-}" ] && envs+=(-e CLAUDE_CODE_OAUTH_TOKEN)
[ -n "${ANTHROPIC_API_KEY:-}" ] && envs+=(-e ANTHROPIC_API_KEY)
PERSONA_TOKEN=$token docker run --rm "${envs[@]}" "${camount[@]}" \
  -v "$out:/out" "$image" "$persona" "$scenario"
