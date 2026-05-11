# xournal-plugins

Eine Sammlung von Plugins für [Xournal++](https://xournalpp.github.io/) –
geschrieben in Lua mit der offiziellen [Plugin-API](https://github.com/xournalpp/xournalpp/blob/master/plugins/luapi_application.def.lua).

Autor: **Florian Klaner** ([@digiflo](https://github.com/digiflo))

## Verfügbare Plugins

| Plugin | Beschreibung |
|--------|--------------|
| [PageRotator](PageRotator/) | Dreht PDF-Hintergrundseiten des aktuellen Dokuments (90°, 180°, 270°). Praktisch für PDFs, die in falscher Orientierung geöffnet werden. |

## Installation

Jedes Plugin liegt in einem eigenen Unterordner. Kopiere den gewünschten
Plugin-Ordner in dein Xournal++-Plugin-Verzeichnis:

| Plattform | Plugin-Verzeichnis                                   |
|-----------|------------------------------------------------------|
| Linux     | `~/.config/xournalpp/plugins/`                       |
| macOS     | `~/.config/xournalpp/plugins/`                       |
| Windows   | `%APPDATA%\xournalpp\plugins\`                       |

Beispiel (Linux/macOS):

```sh
git clone https://github.com/digiflo/xournal-plugins.git
cp -r xournal-plugins/PageRotator ~/.config/xournalpp/plugins/
```

Xournal++ neu starten – das Plugin ist anschließend unter dem Menü
`Plugin` verfügbar (ggf. im `Plugin Manager` aktivieren).

## Entwicklung & Tests

Voraussetzungen: `lua`, `luacheck`, `qpdf`, `python3` mit `reportlab` und `pypdf`.

```sh
tests/run_all.sh
```

Die Testsuite besteht aus drei Schichten:

- **Unit-Tests** ([tests/test_rotation.lua](tests/test_rotation.lua)) – die Plugin-Logik gegen einen Mock der Xournal++-`app`-API
- **Editor-Tests** ([tests/test_xopp_edit.lua](tests/test_xopp_edit.lua)) – der gzip-XML-Editor isoliert
- **End-to-end Tests** ([tests/test_e2e.lua](tests/test_e2e.lua)) – echte `qpdf`-Aufrufe gegen Test-Fixtures, Verifikation via `pypdf`

CI läuft auf GitHub Actions ([.github/workflows/ci.yml](.github/workflows/ci.yml)).

## Lizenz

[MIT](LICENSE)
