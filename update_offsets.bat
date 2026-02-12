@echo off
setlocal

REM Put dump.h AND/OR dump.json in this same folder, then double-click this file.
REM The script will merge offsets from both files if both exist.
REM This will update both C++ format (dumped.html) and JSON format (jsonoffsets.html)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0update_offsets.ps1" -DumpPath "%~dp0dump.h" -DumpJsonPath "%~dp0dump.json" -DumpedPath "%~dp0dumped.html" -JsonOffsetsPath "%~dp0jsonoffsets.html"

echo.
echo Done. You can put:
echo   - dump.json only
echo   - dump.h only
echo   - BOTH dump.json AND dump.h (will merge them)
echo.
echo Updated files:
echo   - dumped.html (C++ format)
echo   - jsonoffsets.html (JSON format)
echo   - fflags.html (preview list, if exists)
echo.
echo If you see an error above, make sure at least one of dump.h or dump.json exists.
pause
endlocal
