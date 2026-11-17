#!/usr/bin/env bash
# Host / CI side of a run: credentials from Vault -> short-lived token ->
# runner container with only that token. Prints no secret.
# usage: runner/run.sh <persona> <scenario>
#
# Environment (the lab binding, kept in the private fleet repo):
#   VAULT_ADDR, VAULT_TOKEN  read access to ai-personas/<lab>/<persona>
#   LAB                      e.g. labul (Vault path segment)
#   CLAIM_API_URL, ORDER_API_URL
#   ANTHROPIC_API_KEY
#   OIDC_CA_FILE             optional: CA bundle for the ZITADEL token URL
#   IMAGE                    default ai-personas-runner:local
#   OUT_DIR                  default ./runs
set -euo pipefail
persona=${1:?persona}; scenario=${2:?scenario}
: "${LAB:?LAB}" "${CLAIM_API_URL:?}" "${ORDER_API_URL:?}" "${ANTHROPIC_API_KEY:?}"
image=${IMAGE:-ai-personas-runner:local}
out=${OUT_DIR:-$PWD/runs}; mkdir -p "$out"

creds=$(vault kv get -format=json "ai-personas/$LAB/$persona" | jq -c .data.data)
ca=(); [ -n "${OIDC_CA_FILE:-}" ] && ca=(--cacert "$OIDC_CA_FILE")
token=$(curl -fsS "${ca[@]}" "$(jq -r .token_url <<<"$creds")" \
  --data-urlencode grant_type=client_credentials \
  --data-urlencode "client_id=$(jq -r .client_id <<<"$creds")" \
  --data-urlencode "client_secret=$(jq -r .client_secret <<<"$creds")" \
  --data-urlencode "scope=$(jq -r .scope <<<"$creds")" | jq -r '.access_token // empty')
unset creds
[ -n "$token" ] || { echo "no token for persona $persona" >&2; exit 1; }

# Values go in by name only (-e VAR), so they never appear in ps or logs.
PERSONA_TOKEN=$token docker run --rm \
  -e PERSONA_TOKEN -e ANTHROPIC_API_KEY -e CLAIM_API_URL -e ORDER_API_URL -e RUN_ID \
  -v "$out:/out" \
  "$image" "$persona" "$scenario"
