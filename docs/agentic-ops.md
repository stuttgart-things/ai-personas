# Von AI-Personas zu Agentic Ops

Stand: 2026-11-23 · Status: Konzept, zur Diskussion

Die Personas bestellen heute schon VMs, warten, bis diese gebaut sind, melden sich an, prüfen sie und bauen sie wieder ab (`verify-vm-ssh-auto`, `delete-vm-auto`). Das ist technisch dieselbe Arbeit wie ein Betriebsauftrag der Form „bau Maschine XY und verifizier sie". Dieses Papier ordnet ein, wie groß der Schritt vom Testen mit KI zum Betreiben mit KI ist, welche Begriffe dafür passen und in welchen Stufen man ihn gehen kann, ohne die Prinzipien aus [`concept.md`](concept.md) aufzugeben.

Kurzfassung: Der technische Sprung ist klein. Was sich ändert, sind Identität, Verantwortung und der Umgang mit Fehlern. KI lohnt sich im Betrieb als Schicht über der Automatisierung, die Absichten übersetzt und Fehler deutet, nicht als Ersatz für Pipelines.

## Begriffe

| Begriff | Was gemeint ist | Bezug zu uns |
| --- | --- | --- |
| **AIOps** | Begriff von Gartner (seit etwa 2016): Machine Learning auf Betriebsdaten, also Anomalie-Erkennung, Event-Korrelation, Alarmbündelung, Hinweise auf Ursachen. Die KI analysiert, sie handelt nicht. | nur am Rand; wer „AI-Ops" sagt, wird oft so verstanden |
| **Agentic Testing / Synthetic Users** | Ein LLM-Agent spielt einen echten Nutzer durch, mit dessen Rechten und Werkzeugen, und bewertet die Erfahrung | das, was ai-personas heute macht |
| **Synthetic Monitoring / Canary** | regelmäßige Probe-Transaktionen gegen das laufende System, um Ausfälle zu sehen, bevor Nutzer sie melden | Stufe 2 unten |
| **Agentic Ops** (auch „AI SRE", agentenbasierter Betrieb) | Ein Agent führt Betriebsaufgaben aus: provisionieren, prüfen, diagnostizieren, Changes vorschlagen | das Ziel dieses Papiers |
| **Intent-based Operations** | Der Mensch sagt, *was* er braucht; das System leitet ab, *wie* | die Schnittstelle, die Agentic Ops anbietet |

Wir verwenden in diesem Repo **Agentic Ops** für „KI führt Betriebstätigkeiten aus" und **AIOps** nur im engeren Sinn der Betriebsdaten-Analyse.

## Was schon da ist

Die Prinzipien der Personas sind genau die Leitplanken, die ein Agent im Betrieb braucht:

| Prinzip bei ai-personas | Bedeutung im Betrieb |
| --- | --- |
| Rechte aus der Identität (ZITADEL), nicht aus dem Prompt | Was der Agent nicht darf, lehnt die API ab, egal was im Prompt oder in einer Tool-Ausgabe steht |
| Nur die Oberfläche eines Users (claims, Bestelldienst; kein kubectl, kein Vault, kein Git-Token) | Der Agent kann nichts, was nicht auch über das Produkt geht; jeder Weg ist ein geprüfter Weg |
| Handeln und Prüfen getrennt, Verifier deterministisch | „Fertig" entscheidet Code, nicht das Modell |
| Jede Änderung ist ein Pull Request; `merge: human \| auto` ([ADR 0004](adr/0004-merge-im-szenario.md)) | Audit-Trail und Freigabe sind schon gebaut; Auto-Merge-Regeln des Management-Clusters begrenzen die Autonomie je Gruppe, Template und Größe |
| Aufräumen, Budget und TTL liegen beim Runner ([ADR 0007](adr/0007-runner-raeumt-auf.md)) | Lebenszyklus und Kosten hängen nicht davon ab, dass das Modell daran denkt |
| `requested-by` auf allem, was eine Persona anlegt | Herkunft jeder Ressource ist nachvollziehbar |

## Was sich ändert

| | Test heute | Betrieb |
| --- | --- | --- |
| Auftrag | Szenario-YAML | Wunsch eines Menschen, Ticket, Alarm |
| Identität | eigener Test-User `persona-<name>` | Agent **im Auftrag von** einem Menschen (On-Behalf-Of, z. B. OAuth Token Exchange nach RFC 8693), oder ein eigener Betriebs-User mit eng geschnittenen Rollen |
| `requested-by` | `user:default/persona-developer` | der Mensch, mit dem Agenten als Akteur daneben |
| Ergebnis | Friction ist der Befund | Fehler müssen gelöst oder an einen Menschen eskaliert werden |
| Lebensdauer | Cleanup, TTL | Ressource bleibt, braucht Owner und Kostenstelle |
| Urteil | Selbsteinschätzung der Persona plus Verifier | nur Verifier |
| Umgebung | Lab, Wegwerf-Ressourcen | auch Ressourcen, an denen andere arbeiten |

### Was die Läufe bisher zeigen

Die fünf Läufe von `verify-vm-ssh-auto` (19. bis 21.11.2026) endeten in der Selbsteinschätzung der Persona mit *nein, ja, ?, teilweise, ja*. Die Ursachen lagen nicht im Modell, sondern in der Plattform:

- Auto-Merge griff nicht, die Bestellung stand ohne Begründung auf `PROpen`.
- Die Bestellung scheiterte, weil ein Branch eines früheren Laufs noch existierte.
- SSH-Login ohne passenden Schlüssel, ohne Hinweis, wie man einen bekommt.
- SSH-Versuch, während die VM noch im Status `Building` war.

Für Tests ist das der gewünschte Ertrag. Für den Betrieb folgt daraus zweierlei: Das Modell darf nie selbst entscheiden, ob etwas fertig ist, und jede dieser Stellen braucht eine maschinenlesbare Antwort (Status, Grund, nächster Schritt), damit ein Agent sie lösen oder sauber eskalieren kann. Friction aus den Persona-Läufen ist damit direkt die Arbeitsliste für ops-taugliche Schnittstellen.

## Wo KI im Betrieb hilft und wo nicht

Faustregel: **Das Modell entscheidet *was*, das deterministische System macht das *wie*, Code prüft *ob*.**

Nicht sinnvoll:

- Immer gleiche Abläufe durch ein Modell laufen lassen. „VM bauen und SSH prüfen" für jede Bestellung gehört als Verifier in die Pipeline, ohne Modell: billiger, schneller, reproduzierbar.
- Das Modell als Freigabe-Instanz. Freigaben bleiben Regeln des Bestelldienstes oder Menschen.

Sinnvoll:

- **Absicht übersetzen:** „kleiner RKE2-Cluster für Team X zum Testen, eine Woche" → Template, Parameter, Owner, TTL.
- **Mehrdeutigkeit auflösen:** nachfragen statt raten, wenn Größe, Team oder Lab unklar sind.
- **Fehler deuten:** Bestellstatus, PR-Checks und Ereignisse lesen und den nächsten Schritt vorschlagen („Order hängt auf PROpen, weil Check X rot ist").
- **Day-2-Diagnose:** zuerst nur lesen (Status, Logs, Metriken), dann einen Change als Pull Request vorschlagen.
- **Zusammenfassen:** für den Menschen in einem Satz, was bestellt, gebaut und geprüft wurde.

## Was die AI bestimmt

Die AI wählt Template und Werte, aber nur innerhalb des Rahmens, den die Automatisierung vorgibt und selbst prüft. Sie schlägt eine Bestellung vor, sie baut nichts. Was gebaut wird, steht danach als Claim im Pull Request, nicht im Prompt.

| Schicht | Wer entscheidet | Womit |
| --- | --- | --- |
| Was überhaupt möglich ist | Plattform-Team, im Template | `enum`, `pattern`, Defaults, `hidden`, `showWhen`/`enumWhen`, `orderRoles`, eingeschränkte Template-Varianten |
| Was bestellt wird | AI schlägt vor, Mensch oder Regel bestätigt | Template-Wahl und Parameter |
| Wie gebaut wird | nur die Automatisierung | KCL rendert, Crossplane baut, Verifier prüfen |

Die AI wählt aus einer Speisekarte, sie kocht nicht: keine KCL-Module, keine freien Manifeste, keine Werte außerhalb des Templates. Versucht sie es, lehnt `CheckParams` mit 400 ab; ein Template ohne passende Rolle gibt 403.

Die Parameter einer Bestellung fallen in drei Gruppen:

| Art | Beispiel | Quelle |
| --- | --- | --- |
| Fest | Image-Quelle, Netz, Policies | Template (Default oder `hidden`); die AI fasst sie nicht an |
| Abgeleitet | Owner/Team, Lab, `requested-by` | Identität und Kontext (Rollen im Token, Lab-Bindung), kein Raten |
| Gewählt | Template, Größe, Anzahl Nodes, Laufzeit | Hier liegt der Mehrwert: aus „klein, zum Testen, eine Woche" werden Werte |

Regeln:

- **Herkunft je Wert:** Für jeden gewählten Wert nennt die AI die Quelle: „vom User gesagt", „Default des Templates" oder „Annahme, weil …".
- **Nachfragen statt raten**, wenn es auf den Wert ankommt (Team, Lab) und der Auftrag ihn nicht hergibt.
- **Vorschau vor der Bestellung:** Render ohne Bestellung (`claims render --stdout`, Preview mit `notify=false`).
- **Bestätigung:** durch einen Menschen im Pull Request (Absicht im Originalwortlaut, Werte mit Begründung, gerenderter Claim) oder durch eine Auto-Merge-Regel des Bestelldienstes. Die Regel ist bewusst keine AI-Entscheidung.
- **Der Claim ist das Ergebnis, nicht der Prompt.** Dieselbe Absicht kann beim nächsten Mal andere Werte ergeben. Wer nachbauen will, nimmt den Claim aus dem Git, nicht die AI.

Folgerung für Templates: Je weniger Freiheitsgrade, desto sicherer kann die AI sie befüllen. T-Shirt-Größen als `enum` statt freier Werte für CPU und RAM; für Entwickler und Agenten eigene Varianten mit eingeschränkten Größen und passenden `orderRoles`. Wer seine Werte genau kennt, braucht keine AI: Formular oder CLI sind dann schneller und eindeutiger. Die AI lohnt sich, wo die Absicht unscharf ist.

## Assistent vor dem Backstage-Formular

Umfangreiche Templates („VM bestellen mit späterer Provisionierung") überfordern manche User, auch wenn das eigentlich eine Designfrage des Templates ist. Ein Assistent kann solche bestehenden Templates nutzbar machen, ohne sie umzubauen: Er übersetzt eine Beschreibung in Text oder Sprache in ein **vorausgefülltes Formular**, das der User prüft und selbst abschickt.

```text
Sprache / Text  ->  Text  ->  AI ordnet zu  ->  vorausgefülltes Formular  ->  User prüft und schickt ab
"kleine Ubuntu-VM   (STT)     Template +        Felder markiert:              normaler Scaffolder-Lauf:
 für zwei Wochen,             Parameter         gesagt / Annahme / Default    Validierung, PR, Merge-Regeln
 mit Docker drauf"
```

1. **Eingabe:** Text oder Sprache. Sprache ist nur ein vorgeschalteter Speech-to-Text-Schritt (Spracherkennung des Browsers oder ein Whisper-Modell); danach ist alles Text.
2. **Template wählen:** aus dem Katalog, über Titel, Beschreibung und Tags der Scaffolder-Templates bzw. die Claim-Templates von claim-machinery-api.
3. **Parameter setzen:** aus dem Parameter-Schema des Templates (Scaffolder-API `parameter-schema`; bei Claim-Templates `enum`, `pattern`, `showWhen`/`enumWhen`), nach den Regeln aus „Was die AI bestimmt".
4. **Formular öffnen:** Der Scaffolder öffnet ein Template mit vorbelegten Werten (`formData` in der URL). Der User sieht das gewohnte Formular.
5. **Abschicken:** durch den User, mit seiner Backstage-Identität. Ab da läuft alles wie heute.

Warum vorausfüllen statt direkt ausführen:

- Der Mensch sieht jeden Wert, bevor etwas passiert (Stufe 3).
- Bestehende Templates funktionieren sofort.
- User lernen das Formular kennen, statt dass es hinter einem Chat verschwindet.
- Die AI hat keine eigenen Rechte; abgeschickt wird mit der Identität des Users.

Direkt ausführen ginge auch: Backstage kann Scaffolder-Aktionen per MCP für Agenten bereitstellen. Das ist der Schritt zu Stufe 4 und kommt danach.

Zu beachten:

- **Felder kennzeichnen:** Jedes Feld zeigt seine Herkunft; Annahmen sind hervorgehoben, damit der User genau die prüft.
- **Pflichtfelder ohne Quelle** bleiben leer oder werden nachgefragt; das Formular blockiert leere Pflichtfelder ohnehin.
- **Sprache trägt Absichten, keine Bezeichner.** „Klein, zwei Wochen, mit Docker" funktioniert; exakte VM-Namen oder Adressen werden oft falsch erkannt. Deshalb ist die Bestätigung im Formular hier Pflicht.
- **Datenschutz:** Audio und Text gehen an einen STT-Dienst und ein LLM. Bei Bedarf lokal (Whisper im Cluster) oder über einen freigegebenen Anbieter.
- **Bedingte Felder:** Der Assistent beachtet `showWhen`/`enumWhen`, am besten mit derselben Logik wie claims und claim-machinery-api, damit er keine Werte für ausgeblendete Felder vorschlägt.
- **Testen mit Personas:** Ein Szenario wie „`newcomer` beschreibt in eigenen Worten, was er braucht" prüft, ob der Assistent das richtige Template und sinnvolle Werte wählt. Mit der Oberfläche `backstage-browser` aus [`concept.md`](concept.md) geht das durch das echte Formular.

## Stufenplan

Jede Stufe ist für sich nützlich. Keine braucht neue Rechte für das Modell, bevor die vorige trägt.

1. **Verifier als Abnahme für echte Bestellungen.** `xr-ready`, `ssh-login` und weitere Verifier laufen nach jeder echten Bestellung und hängen ihr Ergebnis an die Order. Keine KI nötig. Dafür müssen die Verifier aus `verifiers/` unabhängig vom Runner aufrufbar sein.
2. **Personas als Canary.** Ausgewählte Szenarien (`verify-vm-ssh-auto`, `delete-vm-auto`) laufen nächtlich je Lab. Ein roter Lauf ist ein Betriebssignal, nicht nur ein Testergebnis, und geht über denselben homerun-Weg an den Betrieb. Grenzen aus `concept.md` gelten weiter: Lab-Kapazität, Budget, höchstens täglich.
3. **Ops-Assistent mit `merge: human`.** Ein Mensch formuliert die Absicht (CLI, später Backstage oder Teams, auch per Sprache), der Agent wählt Template und Parameter (Abschnitte „Was die AI bestimmt" und „Assistent vor dem Backstage-Formular"), bestellt im Auftrag dieses Menschen und meldet den Pull Request. Ein Mensch merged. Voraussetzung: On-Behalf-Of-Token, damit `requested-by` und die Rechte die des Menschen sind.
4. **Begrenzte Autonomie.** Auto-Merge für risikoarme Klassen (kleine VMs, Lab, mit TTL), gesteuert ausschließlich über die Regeln des Bestelldienstes. Kontingente je Auftraggeber; Verifier entscheiden über „fertig", bei Rot eskaliert der Agent statt zu wiederholen.
5. **Day-2-Betrieb.** Der Agent liest Alarme und Status, diagnostiziert und schlägt Änderungen als Pull Request vor (`change-claim/*`, Teardown). Zuerst nur lesend, Schreiben erst mit eigener Entscheidung als ADR.

## Leitplanken

| Risiko | Gegenmaßnahme |
| --- | --- |
| Agent bekommt zu viele Rechte | Rechte nur über ZITADEL-Rollen per PR; Agent-Identitäten nie `backstage-platform`; bei On-Behalf-Of nie mehr als der Auftraggeber |
| Prompt-Injection aus Tool-Ausgaben (API-Antworten, Ausgaben auf der VM, PR-Texte) | wiegt mit Schreibrechten schwerer; Schutz bleibt die Identität, nicht der Prompt; Ausgaben von VMs nicht als Anweisung behandeln |
| Modell hält Fehlschlag für Erfolg | Verifier entscheiden; Selbsteinschätzung nur als Zusatzinformation |
| Zustand geht mit dem Agenten verloren | Zustand liegt im Bestelldienst und im Git, nie im Agenten. Die Lücke aus ADR 0007 (abgebrochener `run`-Pod räumt nicht auf) muss vor Stufe 4 geschlossen sein |
| Doppelte Aktionen bei Wiederholung | Bestellungen idempotent über Order-ID und Branch; Agent wiederholt nicht blind, sondern liest Status |
| Kosten | Budget je Auftrag wie heute je Lauf; Kontingente je Auftraggeber |
| Verantwortung unklar | Der Auftraggeber ist verantwortlich, der Agent ist Werkzeug; beides steht im Pull Request |

## Persona-Läufe als Eval-Suite

Die Szenarien dieses Repos werden zur Abnahme für jeden Ops-Agenten: Ein neues Modell, neue Regeln oder eine neue Oberfläche laufen erst durch die Persona-Szenarien, bevor sie echte Aufträge bekommen. Damit bleibt ai-personas auch dann nützlich, wenn der Betrieb Agenten einsetzt: Die Personas testen die Plattform, und dieselben Szenarien testen den Agenten.

## Offene Fragen

- On-Behalf-Of: Unterstützt unsere ZITADEL-Instanz Token Exchange, und akzeptieren claim-machinery-api und machinery-order-service ein Token mit Akteur (`act`-Claim)?
- Wo läuft der Ops-Agent: als eigener Dienst neben dem Bestelldienst, als Tekton-Lauf wie die Personas, oder als Agent Sandbox (Stufe 2 in `concept.md`)?
- Wohin melden Canary-Läufe: an den Teams-Kanal der Personas oder an den Betrieb?
- Welche Template-Klassen gelten als risikoarm genug für Stufe 4?
- Sprache: Spracherkennung im Browser, Whisper im Cluster oder ein externer Dienst, und was davon ist für Bestellungen freigegeben?
- Braucht es für Stufe 5 eine eigene Oberfläche mit Leserechten auf Cluster-Status, und wie bleibt sie ohne kubectl?
