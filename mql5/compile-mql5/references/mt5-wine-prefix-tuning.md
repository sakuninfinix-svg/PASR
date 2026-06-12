# MT5 Wine Prefix Tuning Reference

Prefix used: `/home/agus/.mt5`

## Known-good registry commands

```bash
WINEPREFIX=/home/agus/.mt5 wine reg add 'HKCU\Software\Microsoft\Windows NT\CurrentVersion' /v CurrentBuildNumber /t REG_SZ /d '19045' /f
WINEPREFIX=/home/agus/.mt5 wine reg add 'HKCU\Software\Microsoft\Windows NT\CurrentVersion' /v CurrentVersion /t REG_SZ /d '10.0' /f
WINEPREFIX=/home/agus/.mt5 wine reg add 'HKCU\Software\Microsoft\Windows NT\CurrentVersion' /v ProductName /t REG_SZ /d 'Windows 10' /f

WINEPREFIX=/home/agus/.mt5 wine reg add 'HKCU\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers' /v 'C:\Program Files\MetaTrader 5\MetaEditor64.exe' /t REG_SZ /d '~ WIN10RUNASADMIN WINELARGEADDRESSAWARE' /f
WINEPREFIX=/home/agus/.mt5 wine reg add 'HKCU\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers' /v 'C:\Program Files\MetaTrader 5\terminal64.exe' /t REG_SZ /d '~ WIN10RUNASADMIN WINELARGEADDRESSAWARE' /f

WINEPREFIX=/home/agus/.mt5 wine reg add 'HKCU\Software\Wine' /v DesktopMode /t REG_SZ /d 'N' /f
WINEPREFIX=/home/agus/.mt5 wine reg add 'HKCU\Software\Wine' /v UseDGA /t REG_SZ /d 'N' /f
WINEPREFIX=/home/agus/.mt5 wine reg add 'HKCU\Software\Wine' /v UseXRandR /t REG_SZ /d 'Y' /f
WINEPREFIX=/home/agus/.mt5 wine reg add 'HKCU\Software\Wine\Explorer' /v Desktop /t REG_SZ /d '1024x768' /f

WINEPREFIX=/home/agus/.mt5 wine reg add 'HKCU\Software\Wine\Direct3D' /v DirectDrawRenderer /t REG_SZ /d 'gdi' /f
WINEPREFIX=/home/agus/.mt5 wine reg add 'HKCU\Software\Wine\Direct3D' /v VideoMemorySize /t REG_SZ /d '512' /f
WINEPREFIX=/home/agus/.mt5 wine reg add 'HKCU\Software\Wine\Direct3D' /v MaxStageUniformVertices /t REG_SZ /d '256' /f
WINEPREFIX=/home/agus/.mt5 wine reg add 'HKCU\Software\Wine\Direct3D' /v UseWineDXGIDLL /t REG_SZ /d 'N' /f
WINEPREFIX=/home/agus/.mt5 wine reg add 'HKCU\Software\Wine\Direct3D' /v StrictShaderMath /t REG_SZ /d 'N' /f
```

## Preferred environment for MetaEditor/terminal runs

```bash
export WINEPREFIX=/home/agus/.mt5
export WINEESYNC=1
export WINEFSYNC=1
export WINEDEBUG="fixme-all,-err:toolbar,-err:sync"
```

## Observed behavior

- `err:toolbar:ToolbarWindowProc unknown msg 0465` remains even after compatibility flags; treat as noise, not fatal.
- CLI compile often exits 0 without creating `.log` or `.ex5`; this is a Wine/MetaEditor limitation in this setup, not a bad command.
