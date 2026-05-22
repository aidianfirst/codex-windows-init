# codex-windows-init

Lightweight Windows initialization scripts for Codex.

## Files

- `scripts/init-codex.ps1`: initializes Codex config and proxy env on Windows.
- `scripts/init-codex.bat`: simple batch entry point that forwards arguments to the PowerShell script.

## Usage

```bat
scripts\init-codex.bat
scripts\init-codex.bat -CodexHome C:\Users\foo\.codex
```

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\init-codex.ps1
```
