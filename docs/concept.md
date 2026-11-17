# AI-Personas: Szenario-Tests mit begrenzten Rechten

Stand: 2026-11-17

AI-Personas testen unsere Plattform so, wie ein bestimmter User sie erlebt: mit dessen Login, dessen Rechten und nur dessen Werkzeugen. Ein Lauf ist `claude -p` mit einer Persona-Datei, einem Szenario und kurzlebigen Credentials. Ergebnis ist ein Report mit harten Checks und einem UX-Urteil.

## Ziel und Prinzipien

Ziel: Szenarien wie „Entwickler bestellt eine VM" oder „neuer Kollege ohne Gruppe versucht es" wiederholbar durchspielen, mit Rechtemodell und User Experience. Anlass war ein manueller Test am 17.11.2026: Hinweise wie „Notifications are off" oder eine Teams-Karte voller nie gesehener Parameter fand erst eine echte Bestellung, kein Unit-Test.

1. **Rechte kommen aus der Identität, nicht aus dem Prompt.** Jede Persona hat einen eigenen ZITADEL-User mit Gruppen und Rollen. Was die API verbietet, kann die Persona nicht, egal was im Prompt steht.
2. **Nur die Oberfläche eines Users.** claims-CLI, Portal, später Backstage. Kein kubectl, kein gh mit Admin-Token, kein Vault, kein SSH.
3. **Keine godlike AI.** Der Agent kennt keine Interna und keine Abkürzungen. Wo ein User hängen bleibt, bleibt die Persona hängen und schreibt es auf.
4. **Ausführen und Bewerten sind getrennt.** Die Persona handelt, ein Verifier mit Leserechten prüft. Was deterministisch prüfbar ist, prüft Code, nicht das Modell.
5. **Alles ist Code und Review.** Personas, Szenarien und Regeln liegen im Git, Änderungen per PR.
6. **Jeder Lauf räumt auf.** Budget, TTL und Pflicht-Cleanup pro Szenario.

## Begriffe

| Begriff | Was es ist | Wo es liegt |
| --- | --- | --- |
| Persona | Eine Rolle mit Identität, Gruppen, erlaubter Oberfläche und Verhaltensregeln („neu im Team, liest keine Doku") | `personas/<name>/persona.yaml` + `rules.md` |
| Szenario | Ein Ziel in User-Sprache, Erwartungen, Budget und Cleanup | `scenarios/<name>.yaml` |
| Lauf | Eine Ausführung: Persona × Szenario × Lab, mit eigener Run-ID | Workflow-Run, Container |
| Verifier | Prüft die Erwartungen mit Leserechten, deterministisch | `verifiers/` (Skripte) |
| Report | Ergebnis eines Laufs: Checks, Friction-Log, UX-Urteil, Kosten | Artefakt + Teams-Karte |

## Ablage

Dieses Repo ist öffentlich und enthält alles Generische. Was Infrastruktur beim Namen nennt, liegt im privaten Fleet-Repo.

| Was | Wo | Warum |
| --- | --- | --- |
| Personas, Szenarien, Surfaces, Verifier, Runner-Image | dieses Repo (public) | generisch, keine Hostnamen, Endpunkte kommen als Parameter |
| Lab-Bindung: Endpunkte, Vault-Pfade, welche Persona in welchem Lab | privates Fleet-Repo | enthält Infra-Namen |
| ZITADEL-User der Personas | privates Fleet-Repo, ZITADEL-Terraform der Labs | wie alle User |
| Workflow, der Läufe startet, Transcripts und Reports | privates Fleet-Repo (Actions) oder Tekton im Cluster | Logs und Artefakte eines öffentlichen Repos sind öffentlich; Transcripts enthalten Hostnamen und API-Antworten |

Kein bestehendes Repo der Orga passt: `claims` ist die CLI, die die Persona benutzt, und soll nicht ihr eigener Testtreiber sein. `k2n` ist AI-Codegenerierung, `blueprints` sind Dagger-Pipelines (dort könnte später ein Runner-Modul liegen).

```text
ai-personas/
  personas/
    developer/
      persona.yaml        # Identität, Rollen, Oberfläche, Budget
      rules.md            # Verhalten in User-Sprache, wird an den System-Prompt angehängt
    newcomer/
  scenarios/
    order-baseos-vm.yaml
    order-for-foreign-team.yaml   # erwartet: abgelehnt, verständlich
  surfaces/               # was eine Oberfläche an Tools freigibt
    claims-cli.json       # claude --settings: allow/deny-Regeln
    no-mcp.json           # leere MCP-Konfiguration
  verifiers/              # deterministische Checks, nur Leserechte
  runner/                 # Image (claude + claims) und run.sh
  docs/
    concept.md            # dieses Dokument
```

## Identitäten

Jede Persona bekommt einen ZITADEL-Machine-User über das bestehende Terraform-Modul `zitadel-oidc-project`. Es kann Machine-User mit Client Credentials und Rollen schon (`var.machine_users`). Die claims-CLI kann laut `claims login --help` OIDC Client Credentials statt Device Flow nutzen.

1. **Anlegen:** Eintrag in den ZITADEL-Terraform-Variablen der Labs (privates Repo), Name immer `persona-<name>`. Rollen wie bei einem echten User. PR + Review, wie heute.
2. **Secret:** Das Client-Secret liegt in Vault, `ai-personas/<lab>/<persona>`. Nie in Git, nie in einem Report.
3. **Pro Lauf:** Der Runner holt das Secret mit einem eigenen Vault-Token (nur Lesen auf `ai-personas/*`), tauscht es gegen ein Access-Token und gibt dem Container nur dieses. Laufzeit = Szenario-TTL.
4. **Kennzeichnung:** Alles, was eine Persona anlegt, trägt sie als `requested-by` (`user:default/persona-developer`). Der Cleanup findet so seine Reste, und echte Bestellungen bleiben unterscheidbar.
5. **Lebenszyklus:** Persona-Ordner gelöscht → Terraform-Eintrag entfernen → User weg. Ein jährlicher Check vergleicht `personas/` mit den `persona-*`-Usern in ZITADEL.

**Gruppen und Rechte** kommen aus den ZITADEL-Projektrollen. claim-machinery-api (`internal/auth/identity.go`) und sthings-backstage mappen sie gleich:

| ZITADEL-Rolle | Backstage-Gruppe | Wirkung |
| --- | --- | --- |
| `backstage-platform` | `group:default/platform-team` | Admin, darf für jeden bestellen |
| `backstage-developer` | `group:default/guests` | normaler Entwickler |
| `backstage-team-<x>` | `group:default/<x>` | Team-Mitglied, Owner-Auswahl im Formular |
| `backstage-beta-<x>` | `group:default/beta-<x>` | sieht in Backstage nur diesen Track (z. B. vm-machinery) |

Eine Persona ist damit ein dedizierter ZITADEL-User mit genau diesen Rollen, z. B. `persona-developer` mit `backstage-developer` und `backstage-team-ai-personas`. Sie bestellt über claims oder später Backstage wie jeder Entwickler. `persona-*` bekommt nie `backstage-platform`.

**Bestimmte Ausführung** („Entwickler bestellt nur kleine VMs"): Ein Template hat `orderRoles`. Ohne passende Rolle antwortet die API mit 403. Eine eigene Template-Variante mit eingeschränkten Größen und `orderRoles: [backstage-developer]` geht also heute schon. Einschränkungen einzelner Parameter je Rolle innerhalb eines Templates gibt es noch nicht; das wäre ein Feature in claim-machinery-api.

Menschliche Test-User (Login per Browser) braucht es erst für Portal und Backstage. Dann über `zitadel-org-users`, Passwort in Vault. MFA bleibt dabei an:

1. **Bevorzugt: TOTP als zweiter Faktor, Seed in Vault.** Der Runner erzeugt den Code mit `oathtool` aus dem Seed. Der Login läuft wie bei einem Menschen, und der MFA-Schritt wird gleich mitgetestet.
2. **Fallback: eigene ZITADEL-Org `ai-personas`** mit eigener Login-Policy ohne erzwungenes MFA, nur für `persona-*`-User; das Projekt per Grant freigegeben. Die Ausnahme bleibt auf eine Org mit reinen Test-Usern begrenzt.

## Ausführung mit claude -p

Ein Lauf ist ein Container mit `claude` und `claims`, gestartet mit genau einem Access-Token der Persona. Die Grenze ziehen drei Ebenen, nicht der Prompt: Identität (ZITADEL), Container (was überhaupt da ist) und Claude-Settings (welche Tools erlaubt sind).

**Container statt Host.** Ein Container ist Pflicht: kein `~/.kube`, kein `~/.ssh`, kein `gh`-Token, kein Credentials-Cache eines Admins. Das Image enthält nur `claude`, `claims` und `curl`.

- **In CI:** ein normaler Container, als Tekton-Pod oder GitHub-Actions-Job. Dazu eine NetworkPolicy mit Egress nur zu claim-machinery-api, ZITADEL und der Anthropic API.
- **Lokal beim Entwickeln:** `docker run` mit demselben Image. Docker Sandboxes (`docker sandbox run claude`) passen auch, sind aber für interaktive Sessions gedacht. Für reproduzierbare Läufe ist das eigene Image der bessere Standard, weil CI und lokal dann identisch sind. Später auf dem Cluster: Agent Sandbox (Abschnitt Stufe 2).

**Bestellen ohne GitHub-Rechte.** Die Persona bestellt über den Order-as-PR-Endpunkt von claim-machinery-api (`POST /api/v1/claim-templates/{name}/order-pr`). Den PR öffnet der Server mit seiner GitHub App. Die Persona braucht damit nur ihr ZITADEL-Token, wie ein User im Portal.

Die claims-CLI (v0.27.0) kann Client Credentials (`--api-oidc-client-id`, `--api-oidc-client-secret`, `--api-oidc-token-url`, `--api-oidc-scope` bzw. `$CLAIM_API_OIDC_*`). Ihr `render --create-pr` erstellt den PR aber selbst per Git-Push und braucht dafür `--git-token`. Den Endpunkt order-pr nutzt sie noch nicht. Im Pilot nimmt die Persona deshalb `claims` zum Ansehen und Rendern und `curl` für order-pr; später soll ein `claims order` über order-pr das ersetzen (Feature in claims).

**Der Aufruf** (`runner/run.sh`, Flags aus `claude --help`):

```bash
claude -p "$(yq .goal scenarios/$SCENARIO.yaml)" \
  --append-system-prompt "$(cat personas/$PERSONA/rules.md)" \
  --settings surfaces/claims-cli.json \
  --setting-sources "" \
  --tools Bash \
  --allowedTools "Bash(claims:*)" "Bash(curl:*)" \
  --strict-mcp-config --mcp-config surfaces/no-mcp.json \
  --max-budget-usd "$(yq .budget.usd personas/$PERSONA/persona.yaml)" \
  --output-format json > run/$RUN_ID/transcript.json
```

- `--setting-sources ""` lädt keine Host- oder Projekt-Settings, nur die der Oberfläche.
- `--tools` und `--allowedTools` begrenzen auf die CLI eines Users (`curl` nur bis `claims order` existiert; die NetworkPolicy begrenzt die Ziele). Alles andere wird im Print-Modus abgelehnt.
- `rules.md` beschreibt Verhalten, keine Rechte: „Du kennst die Plattform nicht. Wenn etwas unklar ist, schreib es als FRICTION auf und probier, was ein Mensch probieren würde."

**Ablauf eines Laufs:**

1. Workflow startet mit Persona, Szenario und Lab.
2. Runner holt das Persona-Secret aus Vault und tauscht es gegen ein kurzlebiges Token.
3. Container läuft `claude -p` bis Ziel erreicht, Budget leer oder Timeout.
4. Verifier laufen außerhalb des Containers mit Leserechten.
5. Cleanup läuft immer, auch bei Fehlschlag.
6. Report geht als Artefakt und Teams-Karte raus.

## Verifikation und UX-Bewertung

Code entscheidet über bestanden oder nicht, das Modell nur über „war das verständlich". So bleibt ein Lauf reproduzierbar, auch wenn die Persona mal einen anderen Weg nimmt.

| Frage | Wer prüft | Beispiel |
| --- | --- | --- |
| Hat es funktioniert? | Verifier-Skript, deterministisch | PR mit `Order-Id` existiert, XR `Ready=True` in 20 min |
| Wurde Verbotenes verhindert? | Verifier-Skript | Bestellung für fremdes Team: HTTP 403, kein PR, keine XR |
| Stimmt, was der User sieht? | Verifier-Skript | Teams-Karte listet genau die Formular-Parameter |
| Hat die Persona es verstanden? | Friction-Log der Persona | „Fehlermeldung nannte das Feld, aber nicht die erlaubten Werte" |
| Wie gut war die UX? | zweiter `claude -p`-Aufruf ohne Tools, liest Transcript + Friction-Log | Note 1–5 pro Schritt, mit Zitat aus dem Transcript |

Das **Friction-Log** ist der eigentliche Gewinn: Die Persona schreibt jede Stelle als Zeile `FRICTION: <wo> | <was erwartet> | <was passiert>`. Der Runner sammelt diese Zeilen aus dem Transcript. Neue Friction gegenüber dem letzten Lauf wird hervorgehoben, nicht jede Wiederholung.

## Ergebnisse und Reporting

Jeder Lauf erzeugt einen `report.json` und eine Teams-Karte über den bestehenden homerun-Weg. Die Karte geht als System `ai-personas` an den omni-pitcher; der notification-catcher bekommt eine eigene Output-Regel, ähnlich `teams-claim-orders`.

```json
{
  "run": "2026-11-18T09-00-developer-order-baseos-vm",
  "persona": "developer", "scenario": "order-baseos-vm", "lab": "labda",
  "checks": [{"verifier": "order-pr", "ok": true}, {"verifier": "xr-ready", "ok": true, "after": "14m"}],
  "friction": ["Formular: Owner-Feld ohne Erklärung, was eine Gruppe ist"],
  "ux": {"score": 4, "summary": "Bestellung klar, Statusverfolgung fehlt"},
  "costUsd": 0.84,
  "cleanup": "ok"
}
```

- **Karte:** Persona, Szenario, bestanden/nicht, neue Friction, Link zum Run.
- **Historie:** Transcripts und Reports als Workflow-Artefakte (90 Tage) im privaten Repo, Zusammenfassung pro Woche.
- **Aus Friction wird Arbeit:** Wiederkehrende Friction wird ein Issue im betroffenen Repo, mit Zitat aus dem Transcript. Anfangs per Hand, später vorgeschlagen vom Lauf selbst.

## Sicherheit, Kosten und Grenzen

| Risiko | Gegenmaßnahme |
| --- | --- |
| Persona-User bekommt zu viele Rechte | Rollen nur per PR; Review wie bei echten Usern; `persona-*` nie Admin |
| Token taucht im Transcript oder Report auf | Token nur als Env im Container; Runner prüft Transcript und Report vor dem Upload auf Token-Muster und bricht sonst ab (Lehre vom 17.11.2026: ein jq-Filter hat einen Credentials-Cache ausgegeben) |
| Persona lässt Ressourcen liegen | Cleanup als eigener Schritt außerhalb des Agenten; TTL-Label; nächtlicher Sweep über alles mit `requested-by: persona-*` |
| Kosten laufen weg | `--max-budget-usd` pro Lauf, Budget in `persona.yaml`; anfangs nur manuell gestartete Läufe |
| Lab-Kapazität | max. VMs pro Persona; Szenarien mit echten VMs nicht öfter als täglich |
| LLM-Urteil schwankt | bestanden/nicht nur aus Verifiern; UX-Note als Trend über mehrere Läufe lesen, nicht als einzelnen Wert |
| Prompt-Injection aus Tool-Ausgaben | Persona hat ohnehin nur User-Rechte; kein Schreibzugriff außer über die API, die ihre Rechte prüft |

Grenze des Ansatzes: Eine Persona findet, was ein neugieriger User findet, nicht was ein Angreifer findet. Für Security-Tests braucht es eigene Szenarien mit ausdrücklichem Auftrag.

## Stufe 2: Agent Sandbox auf Kubernetes

Wenn Läufe regelmäßig oder parallel laufen, wechselt nur der Startweg: vom Tekton-Pod zu [Agent Sandbox](https://github.com/kubernetes-sigs/agent-sandbox) (kubernetes-sigs, SIG Apps, v1.0.11 vom 12.11.2026; [Blogpost](https://kubernetes.io/blog/2026/03/20/running-agents-on-kubernetes-with-agent-sandbox/)). Identität, `claude -p`-Flags und Verifier bleiben gleich.

| Agent Sandbox | Bei uns |
| --- | --- |
| `SandboxTemplate` | eine Vorlage pro Oberfläche: Runner-Image, Ressourcen, Runtime |
| `SandboxClaim` | ein Lauf = ein Claim gegen die Vorlage (Persona × Szenario) |
| `SandboxWarmPool` | vorgewärmte Pods, kein Kaltstart; erst bei vielen Läufen |
| gVisor / Kata als Runtime | Kernel-Isolation für den Agenten, stärker als ein normaler Container |
| Scale-to-zero und Fortsetzen | Szenarien, die lange warten (VM Ready nach ~15 min) |
| stabiler Hostname pro Sandbox | Browser-Personas, Persona und Verifier als Paar |

Voraussetzungen und Einschränkungen:

- **Runtime:** Unsere Cluster haben heute nur die RuntimeClasses `crun` und `nvidia` (Stand 17.11.2026), kein gVisor und kein Kata. Ohne sie bringt Agent Sandbox nur Lebenszyklus und Warm Pools. Stufe 2 also zusammen mit gVisor einführen.
- **Namespace:** eigener Namespace `ai-personas` mit NetworkPolicy, Egress nur zu claim-machinery-api, ZITADEL und der Anthropic API.
- **Betrieb:** ein Controller mehr, als Flux-Bundle wie die anderen Komponenten.
- **Image:** Das Runner-Image hat von Anfang an keine Host-Abhängigkeiten, damit `docker run`, Tekton und Agent Sandbox dasselbe Image starten.

## Später: Backstage

Backstage wird zweimal Teil davon: als Startknopf für Läufe und als Oberfläche, die Personas testen.

1. **Starten:** Ein Scaffolder-Template „Persona-Test starten" mit Auswahl von Persona, Szenario und Lab. Es stößt den Lauf-Workflow per `workflow_dispatch` an, wie heute die Order-Workflows.
2. **Anzeigen:** Personas und Szenarien als Katalog-Entities (`kind: Resource`, `spec.type: ai-persona` / `ai-scenario`), Reports als TechDocs-Seite pro Szenario mit Verlauf.
3. **Testen:** Eine Persona-Oberfläche `backstage-browser` bestellt über das Create-VM-Template wie ein Mensch. Dafür braucht es Browser-Steuerung im Container (Playwright-MCP) und einen menschlichen Test-User mit Passwort-Login.

## Pilot: RKE2-Agent-Test

Der Pilot ist der offene Test von deploy-configure-rke#53: Persona `developer` bestellt auf LabUL (machinery-labul, Proxmox) zwei baseos-VMs, danach prüfen wir RKE2 mit Server + Agent und Cilium auf `127.0.0.1`. Er testet Bestellung, Teams-Karte (claim-machinery-api v0.30.2) und Rechtemodell in einem Lauf.

- [x] Repo `stuttgart-things/ai-personas` anlegen, Struktur und Beispieldateien
- [ ] `runner/Dockerfile` und `runner/run.sh`
- [ ] Machine-User `persona-developer` (Rollen `backstage-developer`, `backstage-team-ai-personas`) in der LabUL-ZITADEL-Konfiguration, Secret in Vault
- [x] Prüfen, ob die claims-CLI Order-as-PR kann: Client Credentials ja, order-pr nein; im Pilot `curl` mit ihrem Token
- [ ] Issue in claims: `claims order` über den order-pr-Endpunkt
- [ ] Szenario `order-baseos-vm` mit zwei VMs (`rke-agt-test-srv`, `rke-agt-test-agt`, small)
- [ ] Erster Lauf lokal mit `docker run`, Transcript lesen, Rules nachschärfen
- [ ] RKE2 Server + Agent: im Pilot noch per Hand mit deploy-configure-rke, nicht durch die Persona
- [ ] Verifier: PR, XR Ready, Teams-Karte, `cilium`-Pods auf dem Agent Ready
- [ ] Cleanup: beide Claims löschen, Persona-Reste prüfen
- [ ] Auswertung: Friction-Log durchgehen, entscheiden, ob es weitergeht

## Entscheidungen und offene Fragen

- Entschieden: dieses Repo public, Lab-Bindung und Läufe im privaten Fleet-Repo (Abschnitt Ablage).
- Entschieden: Gruppen kommen aus ZITADEL-Projektrollen; eine Persona ist ein dedizierter User mit z. B. `backstage-developer` + `backstage-team-ai-personas` (Abschnitt Identitäten).
- Entschieden: claims kann Client Credentials; order-pr kommt als `claims order` (Feature), im Pilot `curl` (Abschnitt Ausführung).
- Offen: Welcher Anthropic-API-Key für Läufe in CI, und mit welchem Monatsbudget?
- Entschieden: Ziel sind beide Labs, die ersten Läufe auf LabUL. Persona-User gibt es dann pro Lab, Lab-Bindung im privaten Repo.
- Vorschlag: Browser-Personas loggen sich mit Passwort + TOTP (Seed in Vault) ein, MFA bleibt an; Fallback eigene Org ohne erzwungenes MFA (Abschnitt Identitäten). Zu prüfen: aktuelle Login-Policy der ZITADEL-Instanzen.
