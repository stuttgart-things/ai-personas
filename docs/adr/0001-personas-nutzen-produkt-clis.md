# 0001: Personas bedienen die Produkt-CLIs, keine Hilfsskripte

- Status: angenommen
- Datum: 2026-11-18

## Kontext

Im Pilot (`developer`, `order-baseos-vm`) konnte die Persona mit der claims-CLI nicht bestellen: `claims render --create-pr` braucht ein Git-Token, und es gab weder eine Liste der Templates noch der Management-Cluster. Die Umgehung war `curl` gegen machinery-order-service. Das scheiterte an `claude -p`, das Bash-Kommandos mit `$VARIABLEN` nicht freigibt. Zum Laufen kam der Pilot erst mit `runner/orders`, einem kleinen Bash-Client, der Token und URL selbst liest.

Damit testete die Persona aber unser Hilfsskript, nicht das Produkt. Jede Lücke, die `runner/orders` überbrückt hat, ist in Wahrheit ein Befund über claims.

## Entscheidung

- Eine Persona benutzt dieselben Werkzeuge wie ein Mensch, in der Rolle, die sie spielt. Für Bestellungen ist das die claims-CLI.
- Die Persona lernt die Werkzeuge wie ein neuer Kollege: über `--help`, Fehlermeldungen und die Doku, die ein Mensch auch hätte. Kein Spickzettel im Szenario, der Kommandos vorgibt.
- Fehlt einem Werkzeug etwas, bauen wir es dort ein (claims ist unser eigenes Werkzeug), statt es im Runner zu ergänzen. Die Lücke ist ein Issue im Werkzeug-Repo.
- Der Runner liefert nur Umgebung: Login (Token im Env), CA, Konfiguration. Er enthält keine Clients für Produkt-APIs.
- claims wird dafür interaktiv für Menschen und programmatisch für Skripte und Agents gebaut (claims, `docs/adr/0001-interactive-and-programmatic.md`). Die Persona nutzt die programmatische Seite, weil `claude -p` kein Terminal hat.

## Folgen

- `runner/orders` wird entfernt, sobald `claims order` und `claims orders` released sind (claims#124, claims#125; hier #9). Die Surface `claims-cli` erlaubt dann nur noch `Bash(claims:*)`.
- Der nächste Pilot-Lauf wiederholt `order-baseos-vm` nur mit claims. Die Zahl der Friction-Zeilen ist der Vorher-Nachher-Vergleich.
- Interaktive Bedienung (Formulare im Terminal) wird mit `claude -p` nicht getestet. Wird sie selbst Testziel, braucht es einen Terminal-Treiber (z. B. tmux), als eigenes Szenario.
