# 0003: SSH auf bestellte VMs mit kurzlebigen Zertifikaten der Vault-SSH-CA

- Status: angenommen
- Datum: 2026-11-18

## Kontext

Nach der Bestellung im Pilot ging es nicht weiter: Für den RKE2-Test auf den bestellten VMs musste ein Mensch einen öffentlichen Schlüssel per Hand auf beide VMs kopieren. Solche Schlüssel bleiben liegen, laufen nicht ab, und niemand sieht, wer sich als welche Persona angemeldet hat.

## Entscheidung

- Vault bekommt eine SSH-Client-CA (SSH Secrets Engine, signierte Zertifikate) auf einem eigenen Mount. Pro Persona gibt es eine Signier-Rolle: nur die erlaubten Login-Namen, Gültigkeit 30 Minuten, die Key-ID nennt die Persona.
- Neu gebaute VMs vertrauen dieser CA (`TrustedUserCAKeys` in sshd), eingerichtet von der Provisionierung. Einzelne Schlüssel auf VMs entfallen.
- SSH ist pro Szenario eine Fähigkeit (`capabilities: [ssh]`), standardmäßig aus. Ist sie an, erzeugt der Runner einen Wegwerf-Schlüssel, lässt ihn von Vault signieren und gibt Schlüssel und Zertifikat in den Container. Die Persona benutzt dann ganz normal `ssh` (ADR 0001).
- Signiert wird mit derselben Vault-Identität, die schon die Zugangsdaten der Persona liest, erweitert um genau ihren Signier-Pfad. Jede Signatur steht im Vault-Audit-Log.
- Der OTP-Modus von Vault (Einmal-Passwörter) wird nicht verwendet, weil er einen Helfer auf jeder VM braucht.

## Folgen

- Lab-Seite (privates Repo): SSH-CA-Mount und Rollen, dokumentiert wie `vault-ai-personas/`; die baseos-Provisionierung hinterlegt den CA-Schlüssel.
- Runner: `ssh` im Image, aber nur nutzbar mit Zertifikat; die Surface erlaubt `Bash(ssh:*)` nur in Szenarien mit der Fähigkeit.
- Nach Ablauf ist das Zertifikat wertlos, auf der VM gibt es nichts aufzuräumen. Ältere VMs ohne CA-Vertrauen bleiben ohne Persona-SSH.
- Umsetzung: #7.
