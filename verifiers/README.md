# verifiers

Deterministische Checks, die nach einem Lauf außerhalb des Persona-Containers laufen, nur mit Leserechten. Sie entscheiden über bestanden oder nicht; das Modell bewertet nur die UX (docs/concept.md, Abschnitt Verifikation).

Geplant für den Pilot:

| Verifier | Prüft |
| --- | --- |
| `order-pr` | je bestellter VM ein PR mit `Order-Id`-Trailer und erwartetem Pfad |
| `teams-card` | Karte `Claim Order (PR): <template>` mit genau den Formular-Parametern |
| `xr-ready` | XR `Ready=True` innerhalb des Timeouts |
| `order-refused` | HTTP 403, kein PR, keine XR |
