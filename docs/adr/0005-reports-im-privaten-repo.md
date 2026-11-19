# 0005: Lauf-Reports liegen in einem privaten Repo

- Status: angenommen
- Datum: 2026-11-19

## Kontext

Jeder Lauf erzeugt `transcript.md`, `transcript.jsonl`, `summary.json` und `friction.txt` (ADR 0002). Bisher blieben sie lokal in `runs/` auf dem Rechner, der den Lauf gestartet hat. Damit lassen sie sich weder teilen noch über Wochen vergleichen. Ins öffentliche ai-personas-Repo dürfen sie nicht, weil sie Hostnamen, IP-Adressen und API-Antworten enthalten.

## Entscheidung

- Die Reports landen in einem **privaten Repo**, das die Lab-Bindung im privaten Flotten-Repo nennt (`runsRepo`). Im öffentlichen Repo steht kein Name.
- Ablage: `runs/<yyyy-mm>/<run-id>/` mit den vier Dateien. Die `README.md` des Repos ist ein generierter Index mit Persona, Szenario, Lab, Merge, Ergebnis, Turns, Kosten und Anzahl der Friction-Zeilen, die neuesten oben.
- `run.sh` legt den Report nach dem Lauf ab (`runner/publish-run`), mit den Git-Zugangsdaten des Hosts oder der CI. Die Persona sieht diese Zugangsdaten nie. Den Container gibt es zu dem Zeitpunkt nicht mehr.
- Abgelegt wird nur, was die Leak-Prüfung bestanden hat. Ein Lauf, in dessen Ausgabe ein Token oder der SSH-Schlüssel auftaucht, bricht vorher ab und löscht seine Ausgabe.
- Die Reports werden direkt auf `main` des Runs-Repos geschrieben, ohne PR. Das Repo enthält nur generierte Daten, und Reviews hätten dort keinen Nutzen. Läuft gleichzeitig ein anderer Lauf, wird neu geklont und noch einmal versucht.
- Schlägt das Ablegen fehl, bleibt der Report lokal liegen, und der Lauf zählt trotzdem. Mit `task publish` lässt er sich nachreichen.

## Folgen

- Läufe sind auf GitHub lesbar und über die Zeit vergleichbar, zum Beispiel Dauer, Kosten und Friction für dasselbe Szenario.
- Wer Läufe startet, braucht Schreibrechte auf das Runs-Repo. In der CI ist das ein eigenes Token, nicht das der Persona.
- Das Runs-Repo wächst mit jedem Lauf um etwa 100 KB. Aufräumen nach Alter kann später kommen.
