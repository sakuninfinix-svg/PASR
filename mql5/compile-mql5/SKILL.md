---
name: compile-mql5
description: "Compile MQL4/MQL5 code with MetaEditor and fix errors."
version: 1.5.0
author: agus
license: MIT
platforms: [linux]
metadata:
  hermes:
    tags: [mql5, metatrader, forex, compilation]
    related_skills: []
---

# Compile MQL5 Skill

Use this skill when the user asks to compile MQL4/MQL5 source files, fix compilation errors, or check their MetaEditor code for problems.

## Prerequisites

- MetaTrader 5 installed via Wine at `~/.mt5/`
- `metaeditor5` wrapper installed at `/home/agus/.local/bin/metaeditor5`
- `iconv` available for UTF-16LE log reading

## How to Compile

1. Verify the source path under the Wine prefix.
2. Run via the local wrapper script:
   ```bash
   /home/agus/.local/bin/metaeditor5 "Z:\\MQL5\\Experts\\MyExpert.mq5"
   ```
3. After the run, check for artifacts:
   - `.ex5` next to the source
   - `.log` next to the source
   - or output in `logs/metaeditor.log`
   If neither exists, treat the compile run as failed despite exit code 0.

## Quick Reference

| Action | Command |
|--------|---------|
| Compile an Expert Advisor | `/home/agus/.local/bin/metaeditor5 "Z:\\MQL5\\Experts\\MyEA.mq5"` |
| Compile an Indicator | same pattern under `Indicators/` |
| Compile a Script | same pattern under `Scripts/` |

## Fixing Errors

When compilation produces errors:

1. Read `MQL5/Experts/<Source>.log` with `iconv -f UTF-16LE -t UTF-8 <log> | tail -n 120`
2. The log shows each file with `error:` / `warning:` lines including line numbers
3. Use `read_file` to inspect the problematic lines
4. Fix the issues and recompile with the wrapper

Validate artifacts after every compile attempt:
- Confirm the compiler actually produced output artifacts (`.log` and `.ex5`)
- If neither was created, do not trust `exit_code`; treat compile as failed and switch to GUI fallback

## Desktop Shortcuts

On Linux desktops, MetaEditor shortcut reuse should point to `/home/agus/.local/bin/metaeditor5` with explicit Wine env, not raw `MetaEditor64.exe`.

Desktop shortcut expected location: `/home/agus/Desktop/metaeditor5.desktop`

Recommended `Exec` line:

```ini
Exec=env WINEPREFIX=/home/agus/.mt5 WINEESYNC=1 WINEFSYNC=1 WINEDEBUG="fixme-all,-err:toolbar,-err:sync" /home/agus/.local/bin/metaeditor5
Path=/home/agus/.mt5/drive_c/Program Files/MetaTrader 5
Terminal=true
StartupNotify=true
StartupWMClass=metaeditor64.exe
```

Do NOT use DOS-style working directories like `/home/agus/.mt5/dosdevices/c:/...`. Use Linux-native `/home/agus/.mt5/drive_c/...` for `Path=`.

## Wrapper availability

`metaeditor5` lives at `/home/agus/.local/bin/metaeditor5`. If the user needs to recreate it, use the POSIX-compatible version preserved in this skill's scripts path: `scripts/metaeditor5_wrapper.sh`. Do not reintroduce bashisms such as arrays, `set -o pipefail`, or `printf %q`; this wrapper is invoked through `/bin/sh` on the user's system.

## Wine Hard Limits for MetaEditor

MetaEditor under Wine on this setup has a known, non-fixable toolbar compatibility issue:
- `err:toolbar:ToolbarWindowProc unknown msg 0465` is a Wine bug, not a config error
- Wine tuning can reduce but not eliminate these messages
- Do not enter repeated compile loops hoping to eliminate toolbar errors

### Confirmed-stable Wine settings for MT5
```bash
export WINEPREFIX=/home/agus/.mt5
export WINEDEBUG="fixme-all,-err:toolbar,-err:sync"
```

### Do NOT use WINEESYNC or WINEFSYNC here
This user's `MetaEditor64.exe` fails to run under Wine when `WINEESYNC=1` or `WINEFSYNC=1` is set. Keep these unset for MetaEditor/terminal launches unless the user explicitly confirms they work in a given session.

## Known Dual-Tree Source Layout
This user's system can expose two copies of PASR sources:
1. Wine tree: `/home/agus/.mt5/drive_c/Program Files/MetaTrader 5/...`
2. Mounted Windows tree: `/media/agus/<UUID>/Users/agsi/AppData/Roaming/MetaQuotes/Terminal/...`

Before patching `PASR*.mq5` / `*.mqh`, confirm the active tree. Do not assume patch location from file paths alone.

## Compile Artifact Locations

Compile logs may appear in **either**:
1. `/home/agus/.mt5/drive_c/Program Files/MetaTrader 5/MQL5/Experts/<Source>.log` (next to source)
2. `/home/agus/.mt5/drive_c/Program Files/MetaTrader 5/logs/metaeditor.log`

Check both locations.

## Silent Compile Failure Pattern

MetaEditor under Wine frequently exits 0 but writes **no** `.ex5` and **no** compile log.

### Detection
```bash
ls -lt "/home/agus/.mt5/drive_c/Program Files/MetaTrader 5/MQL5/Experts"
ls -lt "/home/agus/.mt5/drive_c/Program Files/MetaTrader 5/logs"
```

If the source file's timestamp is newer than any `.ex5`/`.log`, treat it as a silent compile failure.

### Recommended Response
1. Do not rerun `wine ... /compile` more than once consecutively.
2. Check `MQL5/Experts/<Source>.log` first (UTF-16LE), then `logs/metaeditor.log`
3. If no compile log is created, ask user to compile via GUI (F7) and share resulting log
4. Parse the GUI-generated log with `iconv -f UTF-16LE -t UTF-8` and proceed to fix errors

## Common MQL5 Error Patterns

- `'identifier' - undeclared identifier` — missing variable/function declaration
- `'identifier' - semicolon expected` — missing `;`
- `'(' - expression on global scope not allowed` — code outside functions
- `array out of range` — array index exceeds bounds
- `'>' - operand expected` followed by `undeclared identifier` — typically a missing include or mismatched method name on a service locator/registry accessor
