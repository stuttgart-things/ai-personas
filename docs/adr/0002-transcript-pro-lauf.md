# 0002: Lesbares Transcript pro Lauf

- Status: angenommen
- Datum: 2026-11-18

## Kontext

Jeder Lauf schreibt `transcript.jsonl` (`claude -p --output-format stream-json`). Darin steht alles: was die Persona sich überlegt, welches Kommando sie ausführt, was zurückkommt. Für Menschen ist das nicht lesbar (Pilot: 95 KB JSON für 12 Turns). Wer einen Lauf bewerten will, muss aber genau das nachvollziehen: welchen Weg die Persona gegangen ist, wo sie gestockt hat, welche Kommandos sie mit welchem Ergebnis abgesetzt hat.

## Entscheidung

- Der Runner erzeugt nach jedem Lauf aus `transcript.jsonl` ein `transcript.md`, als festen Teil des Ergebnisses neben `summary.json` und `friction.txt`.
- **Kopf:** Lauf-ID, Persona, Szenario, Lab, Modell, Start, Dauer, Turns, Kosten, Ergebnis.
- **Verlauf, chronologisch:** der Text der Persona, jedes Kommando als Codeblock mit Exit-Status und gekürzter Ausgabe (vollständig im JSONL), Zeitstempel relativ zum Start.
- **Schluss:** Friction-Zeilen, entstandene Bestellungen und PRs, abgelehnte Tool-Aufrufe (was die Persona versucht hat, aber nicht durfte).
- **Geheimnisse:** Das Transcript läuft durch denselben Leak-Check wie die übrigen Ausgaben. Schlägt er an, wird nichts geschrieben.
- Der Renderer ist ein eigenes Kommando im Image (`persona-report`), damit er auch alte Läufe nachträglich rendern kann.

## Folgen

- `transcript.md` ist das, was ein Mensch zuerst liest; Issues aus Friction zitieren daraus.
- Umsetzung: #8.
- Dasselbe Format lässt sich später in Backstage oder als Workflow-Artefakt anzeigen.
