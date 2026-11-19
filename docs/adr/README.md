# Architecture Decision Records

Entscheidungen zu ai-personas, je eine Datei, nummeriert. Ein ADR wird nicht umgeschrieben: Ändert sich eine Entscheidung, kommt ein neues ADR, das alte bekommt `Status: ersetzt durch NNNN`.

| ADR | Titel | Status |
|---|---|---|
| [0001](0001-personas-nutzen-produkt-clis.md) | Personas bedienen die Produkt-CLIs, keine Hilfsskripte | angenommen |
| [0002](0002-transcript-pro-lauf.md) | Lesbares Transcript pro Lauf | angenommen |
| [0003](0003-ssh-mit-vault-ssh-ca.md) | SSH auf bestellte VMs mit kurzlebigen Zertifikaten der Vault-SSH-CA | angenommen |
| [0004](0004-merge-im-szenario.md) | Das Szenario legt fest, wer den Pull Request merged | angenommen |
| [0005](0005-reports-im-privaten-repo.md) | Lauf-Reports liegen in einem privaten Repo | angenommen |

Vorlage: Kontext, Entscheidung, Folgen. Vorgeschichte und Begriffe stehen in [`../concept.md`](../concept.md).
