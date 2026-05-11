# Xournal++ PageRotator

Ein Plugin für [Xournal++](https://xournalpp.github.io/), mit dem du PDF-Seiten
des aktuell geöffneten Dokuments drehen kannst (90°, 180°, 270°). Praktisch
für PDFs, die in falscher Orientierung geöffnet werden.

Xournal++ bietet keine direkte API zum Drehen einer Seite. Das Plugin ruft
deshalb [`qpdf`](https://qpdf.sourceforge.io/) extern auf, rotiert die
Hintergrund-PDF und lädt das Dokument anschließend neu.

## Features

- Aktuelle Seite oder alle Seiten drehen
- 90° im Uhrzeigersinn, 90° gegen den Uhrzeigersinn, 180°
- Shortcut `Strg+Shift+R` für 90° im Uhrzeigersinn auf der aktuellen Seite
- Vor jeder Rotation wird automatisch ein Backup der Original-PDF angelegt
  (`<deine.pdf>.bak-<timestamp>`)

## Voraussetzungen

- Xournal++ 1.1 oder neuer (mit Lua-Plugin-Support)
- [`qpdf`](https://qpdf.sourceforge.io/) muss im `PATH` verfügbar sein:
  - Debian/Ubuntu: `sudo apt install qpdf`
  - Fedora: `sudo dnf install qpdf`
  - Arch: `sudo pacman -S qpdf`
  - macOS: `brew install qpdf`
  - Windows: `choco install qpdf`

## Installation

Kopiere den Ordner `PageRotator/` in dein Xournal++-Plugin-Verzeichnis:

| Plattform | Plugin-Verzeichnis             |
|-----------|--------------------------------|
| Linux     | `~/.config/xournalpp/plugins/` |
| macOS     | `~/.config/xournalpp/plugins/` |
| Windows   | `%APPDATA%\xournalpp\plugins\` |

Schnellinstallation:

```sh
git clone https://github.com/digiflo/xournal-plugins.git
cp -r xournal-plugins/PageRotator ~/.config/xournalpp/plugins/
```

Anschließend Xournal++ neu starten. Das Plugin sollte automatisch aktiv sein
(siehe `Plugin > Plugin Manager`, falls nicht).

## Nutzung

1. Öffne in Xournal++ ein PDF (`File > Annotate PDF …`) oder ein xopp-Dokument
   mit PDF-Hintergrund.
2. **Wichtig:** Speichere das Dokument einmal (`Strg+S`), damit das Plugin es
   nach der Rotation neu laden kann.
3. Im Menü `Plugin` einen der Einträge wählen:
   - *Rotate current PDF page 90° clockwise* (Shortcut: `Strg+Shift+R`)
   - *Rotate current PDF page 90° counter-clockwise*
   - *Rotate current PDF page 180°*
   - *Rotate ALL PDF pages 90° clockwise*
   - *Rotate ALL PDF pages 90° counter-clockwise*
   - *Rotate ALL PDF pages 180°*

Das Plugin sichert die Original-PDF neben dem Original (`<datei>.bak-<datum>`),
rotiert die Datei und lädt das Dokument anschließend neu.

## Hinweise & Caveats

- Die Hintergrund-PDF wird überschrieben. Falls dein PDF gleichzeitig in
  anderen Programmen geöffnet ist, schließe diese vorher.
- Vorhandene handschriftliche Annotationen werden **nicht** mitrotiert – sie
  bleiben in ihrer ursprünglichen Lage auf der Seite. Drehe daher idealerweise
  bevor du annotierst.
- Falls das `.xopp` noch nie gespeichert wurde, kann das Plugin nicht neu
  laden. Speichere und öffne dann manuell erneut.

## Lizenz

MIT
