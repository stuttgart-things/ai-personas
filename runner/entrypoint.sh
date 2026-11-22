#!/usr/bin/env bash
# Inside the runner container: one persona, one scenario, one claude -p run.
# usage: persona-run <persona> <scenario>
#
# Environment (set by runner/run.sh, never baked into the image):
#   PERSONA_TOKEN      short-lived ZITADEL access token of the persona (required)
#   CLAUDE_CODE_OAUTH_TOKEN  claude via a Claude subscription (claude setup-token),
#   or ANTHROPIC_API_KEY     claude via the API; one of the two is required
#   CLAIM_API_URL      claim-machinery-api of the lab (templates, render)
#   CLAIM_ORDERS_URL   machinery-order-service of the lab (claims order/orders)
#   LAB                the lab, for the report
#   RUN_ID             defaults to <utc time>-<persona>-<scenario>
#   OUT_DIR            defaults to /out (mount a host directory there)
# Mounted (optional):
#   /etc/ssl/extra/ca.pem   the lab's root CA; added to the system roots for
#                           claims, curl and claude
#   /run/persona-ssh/       id_ed25519 + id_ed25519-cert.pub: a short-lived SSH
#                           certificate from the lab's Vault SSH CA, only for
#                           scenarios with capabilities: [ssh] (ADR 0003)
set -euo pipefail

persona=${1:?persona}; scenario=${2:?scenario}
base=/opt/ai-personas
pdir=$base/personas/$persona
sfile=$base/scenarios/$scenario.yaml
[ -f "$pdir/persona.yaml" ] || { echo "unknown persona: $persona" >&2; exit 2; }
[ -f "$sfile" ] || { echo "unknown scenario: $scenario" >&2; exit 2; }
yaml() { js-yaml "$1" | jq -r "$2"; }
has_cap() { js-yaml "$sfile" | jq -e --arg c "$1" '(.capabilities // []) | index($c)' >/dev/null; }
: "${PERSONA_TOKEN:?PERSONA_TOKEN missing}"
[ -n "${CLAUDE_CODE_OAUTH_TOKEN:-}${ANTHROPIC_API_KEY:-}" ] \
  || { echo "CLAUDE_CODE_OAUTH_TOKEN or ANTHROPIC_API_KEY missing" >&2; exit 1; }
if has_cap ssh && ! { [ -s /run/persona-ssh/id_ed25519 ] && [ -s /run/persona-ssh/id_ed25519-cert.pub ]; }; then
  echo "scenario $scenario wants ssh, but /run/persona-ssh has no key and certificate" >&2
  exit 2
fi

# Lab root CA in addition to the system roots (Go: SSL_CERT_FILE, curl:
# CURL_CA_BUNDLE, node: NODE_EXTRA_CA_CERTS).
if [ -s /etc/ssl/extra/ca.pem ]; then
  cat /etc/ssl/certs/ca-certificates.crt /etc/ssl/extra/ca.pem > /tmp/ca-bundle.pem
  export SSL_CERT_FILE=/tmp/ca-bundle.pem CURL_CA_BUNDLE=/tmp/ca-bundle.pem \
         NODE_EXTRA_CA_CERTS=/etc/ssl/extra/ca.pem
fi

surface=$(yaml "$pdir/persona.yaml" .surface)
budget=$(yaml "$pdir/persona.yaml" .budget.usd)
goal=$(yaml "$sfile" .goal)
# Who merges the order's pull request (ADR 0004): a human (default), or the
# order service itself once the checks pass, where its rules allow it.
merge=$(yaml "$sfile" '.merge // "human"')
case $merge in
  human|auto) ;;
  *) echo "scenario $scenario: merge must be human or auto, not $merge" >&2; exit 2 ;;
esac
# What the runner removes after the persona (ADR 0007): delete-claim tears
# down the persona's orders of this run through the order service, none
# leaves them (e.g. for a follow-up run).
cleanup=$(yaml "$sfile" '.cleanup // "none"')
case $cleanup in
  delete-claim|none) ;;
  *) echo "scenario $scenario: cleanup must be delete-claim or none, not $cleanup" >&2; exit 2 ;;
esac
run_id=${RUN_ID:-$(date -u +%Y-%m-%dT%H-%M)-$persona-$scenario}
out=${OUT_DIR:-/out}/$run_id
mkdir -p "$out"

# claims reads its token from CLAIM_API_TOKEN, the order service from
# CLAIM_ORDERS_URL (ADR 0001: the persona uses claims like a person would).
export CLAIM_API_TOKEN=$PERSONA_TOKEN

settings=$base/surfaces/$surface.json
allowed=("Bash(claims:*)")
context="Dein Werkzeug ist \`claims\`, schon mit deinem Login eingerichtet."
if [ "$merge" = auto ]; then
  context="$context Für diese Test-Bestellung brauchst du kein Review: Mit \`claims order … --auto-merge\` merged der Bestelldienst den Pull Request selbst, sobald die Checks grün sind. Das gilt auch, wenn du etwas wieder löschst."
fi

# SSH only where the scenario asks for it, and only with a certificate.
sshkey=
. /usr/local/lib/persona-nss-user
if has_cap ssh; then
  if [ -s /run/persona-ssh/id_ed25519 ] && [ -s /run/persona-ssh/id_ed25519-cert.pub ]; then
    mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"
    install -m 600 /run/persona-ssh/id_ed25519 "$HOME/.ssh/id_ed25519"
    install -m 644 /run/persona-ssh/id_ed25519-cert.pub "$HOME/.ssh/id_ed25519-cert.pub"
    printf 'Host *\n  User sthings\n  IdentityFile ~/.ssh/id_ed25519\n  StrictHostKeyChecking accept-new\n  BatchMode yes\n  ConnectTimeout 10\n' > "$HOME/.ssh/config"
    sshkey=$(sed -n 2p "$HOME/.ssh/id_ed25519")   # for the leak check
    # the surface's deny of ssh is lifted for this run only
    jq '.permissions.allow += ["Bash(ssh:*)"] | .permissions.deny -= ["Bash(ssh:*)"]' "$settings" > /tmp/settings.json
    settings=/tmp/settings.json
    allowed+=("Bash(ssh:*)")
    context="$context Auf VMs, die du bestellt hast, kommst du mit \`ssh <adresse>\` (als sthings, mit sudo); der Zugang gilt 30 Minuten ab Start."
  fi
fi

started=$(date -u +%Y-%m-%dT%H:%M:%SZ)
claude -p "$goal" \
  --append-system-prompt "$(cat "$pdir/rules.md")

$context" \
  --settings "$settings" \
  --setting-sources "" \
  --tools Bash \
  --allowedTools "${allowed[@]}" \
  --strict-mcp-config --mcp-config "$base/surfaces/no-mcp.json" \
  --max-budget-usd "$budget" \
  --output-format stream-json --verbose \
  > "$out/transcript.jsonl" || echo "claude exited with $?" >&2

# Friction lines from the persona's own text, whole (quotes and all).
jq -r 'select(.type=="assistant") | .message.content[]? | select(.type=="text") | .text' \
  "$out/transcript.jsonl" | grep -oE 'FRICTION: .*' | sort -u > "$out/friction.txt" || true

# Also after a failed or aborted claude run: what was ordered goes away.
cleanup_rc=0
if [ "$cleanup" = delete-claim ]; then
  persona-cleanup "$out" "$started" || cleanup_rc=$?
fi
persona-summary "$out" "$run_id" "$persona" "$scenario" "${LAB:-}" "$merge" "$cleanup" || echo "persona-summary failed" >&2
persona-report "$out" >/dev/null || echo "persona-report failed" >&2

# A credential in the output stops the run here: nothing of it may be kept.
# The persona's Bash sees claude's environment, so all of them are checked,
# transcript.md included; with ssh also the private key.
SSH_KEY_LINE=$sshkey
for v in PERSONA_TOKEN CLAUDE_CODE_OAUTH_TOKEN ANTHROPIC_API_KEY SSH_KEY_LINE; do
  val=${!v:-}
  [ -n "$val" ] || continue
  if grep -qF "$val" "$out"/* 2>/dev/null; then
    rm -rf "$out"
    echo "$v found in the run output; output deleted" >&2
    exit 3
  fi
done

echo "run $run_id: $(wc -l < "$out/friction.txt") friction line(s), output in $out"
# Not an exit code: the report must still be published (ADR 0007).
[ "$cleanup_rc" -eq 0 ] || echo "cleanup incomplete, see $out/cleanup.json" >&2
