# 0004: Das Szenario legt fest, wer den Pull Request merged

- Status: angenommen
- Datum: 2026-11-19

## Kontext

Jede Bestellung endet in einem Pull Request, den ein Mensch merged. Im ersten `verify-vm-ssh`-Lauf musste deshalb jemand danebensitzen und den PR der Persona mergen, solange ihr SSH-Zertifikat (30 Minuten, ADR 0003) noch galt. Für regelmäßige Läufe ist das zu viel Handarbeit. Der menschliche Weg soll aber weiter getestet werden, denn so bestellen echte Nutzer.

machinery-order-service hat dafür Auto-Merge bekommen (dort ADR 0002). Die Bestellung muss es ausdrücklich verlangen (`claims order --auto-merge`), und eine Regel des Management-Clusters muss es erlauben, etwa für die Gruppe der Personas, bestimmte Templates und Größen.

## Entscheidung

- Ein Szenario hat das Feld `merge: human | auto`, Standard ist `human`.
- `human`: wie bisher. Der Lauf wartet, bis ein Mensch merged, und das Ziel sagt der Persona, dass ein Kollege merged.
- `auto`: Der Runner sagt der Persona im Kontext, dass sie für diese Test-Bestellung `--auto-merge` nehmen darf. Den Flag setzt sie selbst, wie ein Mensch, der seine Rechte kennt. Ob sie ihn findet, ist Teil des Tests.
- Der Runner merged nie selbst und hat keine Git-Rechte. Ob gemerged wird, entscheiden allein der Bestelldienst und seine Regeln.
- Fehlt die Regel, lehnt der Dienst die Bestellung mit 403 ab (claims: Exit 3). Die Persona meldet das als Friction. Das Szenario ist dann nicht erfüllt, und das ist so gewollt.
- `merge` steht in `summary.json` und im Kopf von `transcript.md`.

## Folgen

- `verify-vm-ssh-auto` läuft ohne menschlichen Eingriff, sobald für die Personas-Gruppe eine Regel auf machinery-labul existiert (stuttgart-things).
- `verify-vm-ssh` bleibt bei `human` und testet den Weg mit Review.
- Ein Szenario mit einem anderen Wert als `human` oder `auto` bricht mit Exit 2 ab, noch bevor Kosten entstehen.
