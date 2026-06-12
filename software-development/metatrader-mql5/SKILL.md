---
name: metatrader-mql5
title: MetaTrader 5 / MQL5 Compile & Run Workflow
description: End-to-end workflow for compiling and running Expert Advisors (EA), indicators, and scripts for MetaTrader 5 on Linux via Wine. Covers wineprefix path resolution, MetaEditor invocation, compile log reading, and backtest execution.
skillset: [terminal, file, wine, metatrader]
---

# MetaTrader 5 / MQL5 on Linux

## When to use this skill
- User asks to compile, run, or backtest MQL5/MQL4 code in MetaTrader 5
- User mentions MetaEditor, EA, Expert Advisor, backtest, or strategy testing
- Need to locate MetaTrader data folders, includes, or compiled outputs under Wine

## Pre-flight checks

1. Locate wineprefix. Default is often `~/.mt5` or `~/.wine`. Verify:
   - `ls <prefix>/drive_c/Program Files/MetaTrader 5/MetaEditor64.exe`
   - `ls <prefix>/drive_c/users/<user>/AppData/Roaming/MetaQuotes/Terminal/*/MQL5`
2. Confirm MT5 data folder (GUID-named dir) and MQL5 tree structure:
   - `Experts/`, `Indicators/`, `Scripts/`, `Include/`
3. Identify the EA source file and its include dependencies under `MQL5/Include/`.

## Compile workflow

### Preferred: MetaEditor GUI (more reliable under Wine)
```bash
WINEPREFIX=<prefix> wine "<prefix>/drive_c/Program Files/MetaTrader 5/MetaEditor64.exe"
```
Then press **F7** or use menu **Tools → Compile**.

### Alternative: command-line compile
```bash
WINEPREFIX=<prefix> wine "<prefix>/drive_c/Program Files/MetaTrader 5/MetaEditor64.exe" /compile "<source.mq5>" /log
```
- Note: Wine often floods stderr with toolbar UI errors (`ToolbarWindowProc unknown msg 0465`). These are noise and do **not** mean compile failed.

### Reading compile logs
- MetaEditor log: `<prefix>/drive_c/Program Files/MetaTrader 5/logs/metaeditor.log`
- This log is frequently **UTF-16LE** encoded; `tail`/`cat` will show binary gibberish.
- Read via Wine-native tools or use `iconv`:
  ```bash
  iconv -f UTF-16LE -t UTF-8 "<prefix>/drive_c/Program Files/MetaTrader 5/logs/metaeditor.log" | tail -n 50
  ```
- Lines containing `Compile` and `errors` are authoritative. Exit code 0 from MetaEditor does **not** mean compile passed; parse the log or check for `.ex5` output next to source.

## Artifacts
- Compiled EA: `<source_dir>/<name>.ex5`
- Source map: `<source_dir>/<name>.mql5` (if enabled)
- Compiled logs per compile attempt are appended, not overwritten.

## Common pitfalls
- **Wrong working directory / include paths**: MetaEditor must be launched with the same wineprefix that contains the MT5 data folder and the `Include/PASR` (or other include) paths the EA references.
- **Path with spaces**: Always quote paths; backslash-escaping inside wine cmd is fragile. Prefer Wine path translation or full quoting.
- **Toolbar spam**: `err:toolbar:ToolbarWindowProc unknown msg 0465` is harmless Wine UI noise; ignore it.
- **Exit code 0 ≠ success**: MetaEditor may exit 0 even on compile errors. Check the log or the resulting `.ex5` file.
- **Log encoding**: `metaeditor.log` is UTF-16LE. Use `iconv -f UTF-16LE -t UTF-8` before grepping.
- **Multiple terminals**: MT5 can hold several terminal instances under different GUID dirs. Always verify the exact GUID that owns the EA.
- **Console-model gate**: On Linux/Wine, prefer GUI-based compile+run for MT5/MetaEditor over headless `/compile` automation: command-line compile is unstable and can time out without producing reliable CLI output. Verify success from compile logs and `.ex5` artifacts, not exit code or stdout.
- **Conversation style**: When the user switches to Indonesian and asks to continue, treat prior verified state as authoritative. Do not restart prior commands verbatim; continue from the last known state and keep replies concise unless asked otherwise.

## Backtest execution

Once compiled:
1. Launch MT5 terminal:
   ```bash
   WINEPREFIX=<prefix> wine "<prefix>/drive_c/Program Files/MetaTrader 5/terminal64.exe"
   ```
2. In the Strategy Tester: select the EA, symbol, timeframe, and dates.
3. If backtest is to be driven headlessly, use MetaTrader 5 automation (MQL5 `OnTester` / `DllStart` hooks) or Python bridge (e.g., `MetaTrader5` package) rather than screen scraping, when possible.

## Maintained facts for this user

- Active wineprefix: `~/.mt5`
- Active MetaEditor: `~/.mt5/drive_c/Program Files/MetaTrader 5/MetaEditor64.exe`
- Active MT5 data folder: `~/.mt5/drive_c/Program Files/MetaTrader 5/D0E8209F77C8CF37AD8BF550E51FF075/MQL5/...`
- Active include root: `~/.mt5/drive_c/Program Files/MetaTrader 5/D0E8209F77C8CF37AD8BF550E51FF075/MQL5/Include/PASR`
