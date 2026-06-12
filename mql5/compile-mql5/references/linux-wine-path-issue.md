# Linux + Wine + Dual-source Active Bug
- User's system has TWO source trees:
  - Wine-side: under `/home/agus/.mt5/drive_c/Program Files/MetaTrader 5/...`
  - Mounted Windows: `/media/agus/40A604FEA604F666/Users/agsi/AppData/Roaming/MetaQuotes/Terminal/...`
- Patches must be applied to BOTH trees, or verify which one `MetaEditor64.exe` is reading before editing.
- Editing only one tree can miss Wine-side logs/artifacts.
- For compile logs, also read from `logs/metaeditor.log` and `MQL5/Experts/<Source>.log` via UTF-16LE conversion.
