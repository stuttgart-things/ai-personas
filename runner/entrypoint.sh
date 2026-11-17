#!/usr/bin/env bash
# Inside the runner container: one persona, one scenario, one claude -p run.
# usage: persona-run <persona> <scenario>
#
# Environment (set by runner/run.sh, never baked into the image):
#   PERSONA_TOKEN      short-lived ZITADEL access token of the persona (required)
#   CLAUDE_CODE_OAUTH_TOKEN  claude via a Claude subscription (claude setup-token),
#   or ANTHROPIC_API_KEY     claude via the API; one of the two is required
#   CLAIM_API_URL      claim-machinery-api of the lab (templates, render)
#   ORDER_API_URL      machinery-order-service of the lab (ordering)
#   RUN_ID             defaults to <utc time>-<persona>-<scenario>
#   OUT_DIR            defaults to /out (mount a host directory there)
# Mounted file (optional): /etc/ssl/extra/ca.pem, the lab's root CA; added to
# the system roots for claims, curl and claude.
set -euo pipefail

persona=${1:?persona}; scenario=${2:?scenario}
base=/opt/ai-personas
pdir=$base/personas/$persona
sfile=$base/scenarios/$scenario.yaml
[ -f "$pdir/persona.yaml" ] || { echo "unknown persona: $persona" >&2; exit 2; }
[ -f "$sfile" ] || { echo "unknown scenario: $scenario" >&2; exit 2; }
: "${PERSONA_TOKEN:?PERSONA_TOKEN missing}"
[ -n "${CLAUDE_CODE_OAUTH_TOKEN:-}${ANTHROPIC_API_KEY:-}" ] \
  || { echo "CLAUDE_CODE_OAUTH_TOKEN or ANTHROPIC_API_KEY missing" >&2; exit 1; }

# Lab root CA in addition to the system roots (Go: SSL_CERT_FILE, curl:
# CURL_CA_BUNDLE, node: NODE_EXTRA_CA_CERTS).
if [ -s /etc/ssl/extra/ca.pem ]; then
  cat /etc/ssl/certs/ca-certificates.crt /etc/ssl/extra/ca.pem > /tmp/ca-bundle.pem
  export SSL_CERT_FILE=/tmp/ca-bundle.pem CURL_CA_BUNDLE=/tmp/ca-bundle.pem \
         NODE_EXTRA_CA_CERTS=/etc/ssl/extra/ca.pem
fi

yaml() { js-yaml "$1" | jq -r "$2"; }
surface=$(yaml "$pdir/persona.yaml" .surface)
budget=$(yaml "$pdir/persona.yaml" .budget.usd)
goal=$(yaml "$sfile" .goal)
run_id=${RUN_ID:-$(date -u +%Y-%m-%dT%H-%M)-$persona-$scenario}
out=${OUT_DIR:-/out}/$run_id
mkdir -p "$out"

# claims reads its token from CLAIM_API_TOKEN; curl uses PERSONA_TOKEN.
export CLAIM_API_TOKEN=$PERSONA_TOKEN

context="Deine Werkzeuge: die CLI \`claims\` (Templates ansehen und rendern; API: \$CLAIM_API_URL) und \`curl\` für die Bestell-API \$ORDER_API_URL. Dein Login ist bereits gesetzt: claims nutzt ihn automatisch, für curl steht dein Bearer-Token in \$PERSONA_TOKEN. Gib den Inhalt dieser Variablen nie aus."

claude -p "$goal" \
  --append-system-prompt "$(cat "$pdir/rules.md")

$context" \
  --settings "$base/surfaces/$surface.json" \
  --setting-sources "" \
  --tools Bash \
  --allowedTools "Bash(claims:*)" "Bash(curl:*)" \
  --strict-mcp-config --mcp-config "$base/surfaces/no-mcp.json" \
  --max-budget-usd "$budget" \
  --output-format stream-json --verbose \
  > "$out/transcript.jsonl" || echo "claude exited with $?" >&2

# A credential in the output stops the run here: nothing of it may be kept.
# The persona's Bash sees claude's environment, so all three are checked.
for v in PERSONA_TOKEN CLAUDE_CODE_OAUTH_TOKEN ANTHROPIC_API_KEY; do
  val=${!v:-}
  [ -n "$val" ] || continue
  if grep -qF "$val" "$out"/* 2>/dev/null; then
    rm -rf "$out"
    echo "$v found in the run output; output deleted" >&2
    exit 3
  fi
done

grep -ohE 'FRICTION: [^"\\]*' "$out/transcript.jsonl" | sort -u > "$out/friction.txt" || true
jq -s '{run: $run, persona: $p, scenario: $s,
        result: (map(select(.type=="result")) | last | {subtype, is_error, num_turns, total_cost_usd, result})}' \
  --arg run "$run_id" --arg p "$persona" --arg s "$scenario" \
  "$out/transcript.jsonl" > "$out/summary.json" || true
echo "run $run_id: $(wc -l < "$out/friction.txt") friction line(s), output in $out"
