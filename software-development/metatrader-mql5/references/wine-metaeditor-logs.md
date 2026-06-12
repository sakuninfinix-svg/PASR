# MetaEditor / Wine compile logs — session notes

## `metaeditor.log` encoding
- Path: `<prefix>/drive_c/Program Files/MetaTrader 5/logs/metaeditor.log`
- Encoding: **UTF-16LE**.
- Reading with `cat`/`tail` produces unreadable output.
- Read with:
  ```bash
  iconv -f UTF-16LE -t UTF-8 "<path>" | tail -n 50
  ```

- Noise vs real errors
- Harmless Wine UI noise: `err:toolbar:ToolbarWindowProc unknown msg 0465` (many repetitions).
- Also observed (non-fatal): `err:toolbar:ToolbarWindowProc unknown msg 0466`.
- These toolbar messages are not compile failures; they are repeated Wine UI callbacks that still allow MetaEditor to run.
- Real signals: lines containing `Compile` and `errors`, e.g.:
  ```
  Compile C:\...\PASR_PRERELEASE.mq5 - 5 errors, 0 warnings
  ```
- LineFile errors about opening files from `Z:\` paths indicate Wine path translation issues for that compile invocation, not necessarily source errors.

## Exit code behaviour
- MetaEditor often exits `0` even when compile fails. Do not rely on CLI exit code alone.
