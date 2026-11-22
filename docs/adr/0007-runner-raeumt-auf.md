# 0007: Der Runner räumt über den Bestelldienst auf

- Status: angenommen
- Datum: 2026-11-22

## Kontext

Die meisten Szenarien hatten `cleanup: delete-claim`, aber nichts setzte das Feld um. Nach jedem Lauf löschte ein Mensch die VM per `claims delete --create-pr` und räumte den Branch der Bestellung weg. Der Löschweg wurde dabei nie aus Nutzersicht getestet (#27).

Seit machinery-order-service v0.5.0 (dort ADR 0003) gibt es einen Teardown: `claims orders teardown <ord-id>` öffnet einen `delete-claim/<xr>`-Pull-Request, und `delete-claim-xr.yaml` im Flotten-Repo löscht nach dem Merge die XR. Mit `--auto-merge` merged der Dienst den Pull Request selbst. Das geht nur für den Besteller selbst und nur, wenn eine Regel des Management-Clusters Teardowns erlaubt (`actions: [order, teardown]`). Branches entfernt der Dienst nach dem Merge selbst (machinery-order-service#20).

## Entscheidung

- **Löschen als Szenario:** `delete-vm-auto` lässt die Persona bestellen und wieder löschen, beides ohne Review. Ob sie den Weg findet, ist Teil des Tests. Der Kontext verrät ihr nur, dass `--auto-merge` auch beim Löschen gilt.
- **Aufräumen ist Sache des Runners, nicht des Modells.** Bei `cleanup: delete-claim` ruft `persona-run` nach claude `persona-cleanup` auf. Das passiert auch, wenn claude scheiterte oder das Budget aufbrauchte. Der Runner arbeitet mit dem Token der Persona und nur über den Bestelldienst (`claims orders cancel` / `teardown`), ohne Git oder kubectl. `cleanup: none` lässt alles stehen, z. B. für einen Folgelauf (`order-rke-pair`).
- **Was aufgeräumt wird:** die eigenen Bestellungen der Persona (`--mine`), die seit dem Start von claude angelegt wurden, mit 120 s Spielraum für Uhrenabweichung. Eine Persona läuft nie zweimal gleichzeitig, also fällt nichts aus einem anderen Lauf in dieses Fenster.
  - Bestellung noch nicht gemerged: `cancel`.
  - Gemerged bis Ready: `teardown`, mit `--auto-merge`, wenn die Bestellung selbst auto-gemerged war. Lehnt die Regel das ab (Exit 3), geht der Teardown ohne `--auto-merge` raus, und den delete-claim-PR merged ein Mensch.
  - Teardown läuft schon: warten. Deleted, Cancelled oder Failed: nichts zu tun.
- Der Runner wartet auf Deleted bzw. Cancelled, höchstens `CLEANUP_TIMEOUT` lang (Standard 45 Minuten, so lange kann `delete-claim-xr.yaml` brauchen). Auf einen menschlichen Merge wartet er nicht: Er notiert den offenen Pull Request und macht weiter.
- Das Ergebnis steht in `cleanup.json`, in `summary.json` (`cleanup`), im Abschnitt „Aufräumen" von `transcript.md` und als Spalte *Cleanup* im Index des Runs-Repos (`ok`, `open`, `–`). Ein unvollständiges Aufräumen ist **kein Exit-Code**. Der Report muss trotzdem veröffentlicht werden, denn er zeigt, was übrig ist.
- Die Git-Wege von claims (`delete`, `change`, `encrypt`) sind in der Oberfläche `claims-cli` gesperrt. Die Persona hat kein Git-Token, und Löschen soll über den Bestelldienst laufen.

## Folgen

- Nach einem `merge: auto`-Lauf bleiben keine VM und kein Branch übrig, sofern die Regel `persona-test-vms` Teardowns erlaubt (stuttgart-things: `actions: [order, teardown]`).
- `merge: human`-Szenarien hinterlassen einen offenen delete-claim-PR für einen Menschen. Der Report nennt ihn.
- Ein Lauf dauert länger, im Tekton-Beispiel ist der PipelineRun-Timeout deshalb 2h30m. Das ZITADEL-Token muss das Aufräumen überdauern. ZITADEL gibt Access-Tokens standardmäßig 12 Stunden; für diese Instanz ist das nicht geprüft.
- Wird der `run`-Pod abgebrochen (Timeout, Node weg), räumt niemand auf, und es entsteht auch kein Report (`publish` läuft nur nach `run`). Das bleibt eine Lücke, bis ein eigener Cleanup-Task im `finally` mit eigenem Token kommt.
- Der Dapr-Worker des Flotten-Repos merged nur den Branch, den er selbst beobachtet (eine Instanz je Backstage-Ausführung), nicht jeden grünen `delete-claim/*`-PR (geprüft am 22.11.2026, machinery-order-service ADR 0003). Ein delete-claim-PR des Bestelldienstes wird also nur vom Dienst selbst oder von einem Menschen gemerged.
