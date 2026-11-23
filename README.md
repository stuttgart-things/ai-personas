# ai-personas

AI-Personas testen die stuttgart-things-Plattform so, wie ein bestimmter User sie erlebt: mit eigenem ZITADEL-Login, nur dessen Rechten und nur dessen Werkzeugen. Ein Lauf ist `claude -p` in einem Container, mit einer Persona, einem Szenario und einem kurzlebigen Token. Ergebnis ist ein Report mit deterministischen Checks und einem UX-Friction-Log.

Keine godlike AI: Die Rechte zieht die Identität (ZITADEL-Rollen), nicht der Prompt.

**Status:** Konzept und Beispieldateien. Runner, Verifier und der erste Pilot (RKE2 Server + Agent auf LabUL) folgen.

## Inhalt

| Pfad | Was |
| --- | --- |
| [`docs/concept.md`](docs/concept.md) | das Konzept: Prinzipien, Identitäten, Ausführung, Verifikation, Sicherheit, Agent Sandbox, Backstage, Pilot |
| [`docs/agentic-ops.md`](docs/agentic-ops.md) | vom Testen zum Betreiben: Begriffe (AIOps, Agentic Ops), Stufenplan, Leitplanken |
| `personas/<name>/persona.yaml` | Identität, ZITADEL-Rollen, Oberfläche, Budget |
| `personas/<name>/rules.md` | Verhalten in User-Sprache, an den System-Prompt angehängt |
| `scenarios/<name>.yaml` | Ziel in User-Sprache, Erwartungen (Verifier), Cleanup, TTL |
| `surfaces/` | `claude --settings` und MCP-Konfiguration je Oberfläche |
| `verifiers/` | deterministische Checks mit Leserechten (folgt) |
| `runner/` | Container-Image (`claude` + `claims`) und `run.sh` (folgt) |

## Was nicht hier liegt

Dieses Repo ist öffentlich. Lab-Endpunkte, Vault-Pfade, die ZITADEL-User der Personas, der Workflow, der Läufe startet, sowie Transcripts und Reports liegen im privaten Fleet-Repo: Logs und Artefakte eines öffentlichen Repos sind öffentlich.

## Personas

| Persona | ZITADEL-Rollen | Oberfläche |
| --- | --- | --- |
| `developer` | `backstage-developer`, `backstage-team-ai-personas` | claims-CLI + machinery-order-service |
| `newcomer` | `backstage-developer` (kein Team) | claims-CLI + machinery-order-service |
