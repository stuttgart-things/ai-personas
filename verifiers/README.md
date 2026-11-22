# verifiers

Deterministische Checks, die nach einem Lauf außerhalb des Persona-Containers laufen, nur mit Leserechten. Sie entscheiden über bestanden oder nicht; das Modell bewertet nur die UX (docs/concept.md, Abschnitt Verifikation).

Geplant für den Pilot:

| Verifier | Prüft |
| --- | --- |
| `order-pr` | je bestellter VM ein PR mit `Order-Id`-Trailer und erwartetem Pfad |
| `teams-card` | Karte `Claim Order (PR): <template>` mit genau den Formular-Parametern |
| `xr-ready` | XR `Ready=True` innerhalb des Timeouts |
| `order-refused` | HTTP 403, kein PR, keine XR |
| `auto-merged` | der Bestell-PR wurde vom Bestelldienst gemerged (ADR 0004) |
| `teardown-pr` | ein `delete-claim/<xr>`-PR mit `Order-Id`-Trailer, vom Bestelldienst gemerged |
| `xr-deleted` | Order-Phase `Deleted`, machinery sieht die XR nicht mehr, innerhalb des Timeouts |
| `no-branches` | weder `vm-<name>` noch `delete-claim/<xr>` bleiben im Fleet-Repo übrig |
