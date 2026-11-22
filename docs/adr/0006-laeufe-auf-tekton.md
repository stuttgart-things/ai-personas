# 0006: Persona-Läufe auf Tekton, drei Pods mit je eigenem Egress

- Status: angenommen
- Datum: 2026-11-22

## Kontext

Bis #20 startete ein Mensch jeden Lauf mit `runner/run.sh` auf seinem Rechner. Dabei hatte der Host-Prozess gleichzeitig Vault-Token, Git-Rechte und den Claude-Zugang. Der Persona-Container bekam zwar nur das ZITADEL-Token, aber das Netz des Hosts: Er erreichte also Vault, GitHub und alles im Lab. Für regelmäßige Läufe, später auch zeitgesteuert (#17), braucht es eine Ausführung ohne Admin-Rechner, bei der die Grenzen im Cluster erzwungen werden.

Am 21.11.2026 liefen drei Läufe von `verify-vm-ssh-auto` als Tekton-PipelineRuns auf machinery-labul (stuttgart-things/stage-time, `pipelines/execute-persona-run.yaml`). Der dritte (`572ff`) erreichte das Ziel: bestellt, vom Bestelldienst gemerged, VM Ready, SSH-Login.

## Entscheidung

- Ein Lauf ist eine **Pipeline mit drei Pods**. Jeder Pod bekommt nur die Secrets und den Egress, die er braucht:

  | Pod | Secrets | Egress |
  | --- | --- | --- |
  | `credentials` | Vault-AppRole | Vault, ZITADEL |
  | `run` (claude) | Claude-Zugang; das Persona-Token kommt vom ersten Pod | claim-machinery-api, Bestelldienst, ZITADEL, Anthropic API, bei `ssh` die VMs auf Port 22 |
  | `publish` | Git-Token des privaten Runs-Repos (ADR 0005) | github.com |

- Das Persona-Token und der SSH-Schlüssel gehen über ein `credentials/`-Verzeichnis im Workspace vom ersten in den zweiten Pod. `run` verschiebt beides in den Speicher (`emptyDir` mit `medium: Memory`) und löscht es vom Volume, bevor claude startet. Der `finally`-Task `wipe-credentials` löscht `credentials/` in jedem Fall. Er **schlägt fehl, wenn danach noch etwas dort liegt**. Der Workspace ist ein `volumeClaimTemplate` und stirbt mit dem PipelineRun.
- Der Egress des `run`-Pods ist eine CiliumNetworkPolicy im privaten Flotten-Repo (FQDN-Regeln, Label `tekton.dev/pipelineTask: run`). Bevor claude startet, beweist der Schritt **`egress-check`** das Negative: Die Vault-Adresse des `credentials`-Tasks und `egressDenied` (Standard: github.com, api.github.com) dürfen nicht erreichbar sein. Als blockiert gilt nur „keine Verbindung" (curl 6, 7, 28). Kommt eine Verbindung zustande, auch mit TLS-Fehler, bricht der Task ab, und keine Persona läuft.
- Die Pipeline führt standardmäßig nur Szenarien mit **`merge: auto`** aus (ADR 0004). Ein `merge: human`-Szenario hielte den Pod fest, bis jemand merged. Dafür gibt es `allowHumanMerge: "true"`.
- Im `run`-Pod läuft das Image mit seinem unveränderten Entrypoint `persona-run`: dieselbe Logik wie lokal, einschließlich Leak-Check (Exit 3, nichts wird veröffentlicht) und Aufräumen (ADR 0007).
- Das Image wird über den Commit gepinnt: `runnerImage` = `ghcr.io/stuttgart-things/ai-personas-runner:<sha>`, und derselbe sha als `aiPersonasRevision` für `publish-run`.
- `runner/run.sh` bleibt für lokale Läufe bei der Entwicklung. Regelmäßige Läufe gehen über Tekton.

## Folgen

- Kein Lauf braucht mehr einen Admin-Rechner. Eine PipelineRun mit `kubectl create` genügt (Beispiel in der README von stage-time).
- Ob die Grenzen halten, zeigt jeder Lauf selbst: Ein offener Egress lässt den `run`-Task scheitern, ein Rest in `credentials/` den `finally`-Task.
- Der Claude-Zugang liegt als Secret im Cluster. Für die Testphase ist das ein OAuth-Token aus `claude setup-token`, das an das Abo einer Person gebunden ist. Für regelmäßige Läufe ist ein API-Key nötig.
- Ein Lauf, der vor `run` scheitert, hinterlässt kein Token: `wipe-credentials` läuft trotzdem und prüft das Ergebnis. Wird der PipelineRun abgebrochen, bevor `finally` startet, verschwindet das Volume mit dem PipelineRun. Das Token ist dann noch bis zu seinem Ablauf gültig.
- Später: zeitgesteuerte Läufe (#17) und ein PersonaRun-XR, das die Lab-Bindung aus einer EnvironmentConfig liest, statt sie als Params zu übergeben.
