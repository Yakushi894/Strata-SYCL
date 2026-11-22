@echo off
setlocal EnableDelayedExpansion
title Strata BENCH easy launcher
cd /d %~dp0

rem ============================================================
rem  BENCH かんたん起動： GGUF の場所を聞いて、設定（strata-iq3_s-sycl.json）を
rem  自動生成してから純正 BENCH.bat を実行する
rem ============================================================

rem ---------- strata.exe を探す ----------
set "ENGINE="
if exist "%~dp0strata.exe" set "ENGINE=%~dp0strata.exe"
if not defined ENGINE if exist "%~dp00.1.60.1-windows-x86_64-sycl\strata.exe" set "ENGINE=%~dp00.1.60.1-windows-x86_64-sycl\strata.exe"
if not defined ENGINE if exist "%~dp0..\0.1.60.1-windows-x86_64-sycl\strata.exe" set "ENGINE=%~dp0..\0.1.60.1-windows-x86_64-sycl\strata.exe"
if not defined ENGINE (
  echo strata.exe が自動で見つかりませんでした。
  set /p "ENGDIR=パッケージフォルダ（strata.exe のある場所）を入力してください: "
  if defined ENGDIR set "ENGDIR=!ENGDIR:"=!"
  if exist "!ENGDIR!\strata.exe" set "ENGINE=!ENGDIR!\strata.exe"
)
if not defined ENGINE (
  echo strata.exe が特定できませんでした。
  pause
  exit /b 1
)
echo engine : %ENGINE%
echo.

rem ---------- GGUF（パック）フォルダを聞く ----------
set /p "PACK=GGUF（パック）のフォルダを入力してください（ドラッグ＆ドロップ可）: "
if defined PACK set "PACK=%PACK:"=%"
if not exist "%PACK%" (
  echo フォルダがありません: %PACK%
  pause
  exit /b 1
)

echo.
echo --- %PACK% 内の .gguf ---
set COUNT=0
for /f "delims=" %%F in ('dir /b /on "%PACK%\*.gguf" 2^>nul') do (
  set /a COUNT+=1
  set "FILE!COUNT!=%%F"
  echo   !COUNT!: %%F
)
if %COUNT%==0 (
  echo .gguf ファイルが見つかりませんでした。
  pause
  exit /b 1
)

set DEF_PLE=2
if %COUNT%==1 set DEF_PLE=1
echo.
echo 本体シャード（--native）は通常 1 番、PLEシャード（--ple-gguf）は通常 %DEF_PLE% 番です。
set /p "NSEL=--native の番号 [1]: "
set /p "PSEL=--ple-gguf の番号 [%DEF_PLE%]: "
if "%NSEL%"=="" set NSEL=1
if "%PSEL%"=="" set PSEL=%DEF_PLE%
for /f "delims=0123456789" %%A in ("%NSEL%") do set NSEL=1
for /f "delims=0123456789" %%A in ("%PSEL%") do set PSEL=%DEF_PLE%
if %NSEL% LSS 1 set NSEL=1
if %NSEL% GTR %COUNT% set NSEL=1
if %PSEL% LSS 1 set PSEL=%DEF_PLE%
if %PSEL% GTR %COUNT% set PSEL=%DEF_PLE%
call set "NATIVE=%%FILE%NSEL%%%"
call set "PLE=%%FILE%PSEL%%%"

rem ---------- pack dir (merged.gguf + pack folder layout) ----------
set "PACKDIR=%PACK%"
if exist "%PACK%\pack\native_experts.txt" set "PACKDIR=%PACK%\pack"
if not "%PACKDIR%"=="%PACK%" echo pack dir: %PACKDIR% (native_experts.txt found)

rem ---------- tokenizer ----------
set "TOK=%PACKDIR%\tokenizer"
if not exist "%TOK%\vocab.json" (
  echo.
  echo パック内に tokenizer\vocab.json が見つかりません。
  set /p "TOK=tokenizer フォルダ（vocab.json のある場所）を入力してください: "
  if defined TOK set "TOK=!TOK:"=!"
  if not exist "!TOK!\vocab.json" echo 警告: !TOK!\vocab.json がありません（サーバ起動時にエラーになります）
)

rem ---------- MTP（任意） ----------
echo.
set /p "MTPD=MTP のフォルダ（無ければそのまま Enter）: "
if defined MTPD set "MTPD=%MTPD:"=%"

rem ---------- 設定 JSON を生成 ----------
set "BKIT_EXE=%ENGINE%"
set "BKIT_PACK=%PACKDIR%"
set "BKIT_NATIVE=%PACK%\%NATIVE%"
set "BKIT_PLE=%PACK%\%PLE%"
set "BKIT_TOK=%TOK%"
set "BKIT_MTP=%MTPD%"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$a=New-Object System.Collections.ArrayList; [void]$a.AddRange(@('--pack',$env:BKIT_PACK,'--native',$env:BKIT_NATIVE,'--ple-gguf',$env:BKIT_PLE,'--expert-cache','auto','--stream-experts','--prefill','auto','--spec','4','--spec-min-p','0.5','--max-context','32768','--kv','int8','--vram-reserve-mib','1024')); if($env:BKIT_MTP){[void]$a.Add('--mtp');[void]$a.Add($env:BKIT_MTP)}; [void]$a.Add('--serve'); $cfg=[ordered]@{engine='strata';backend='sycl';exe=$env:BKIT_EXE;args=@($a.ToArray());env=[ordered]@{SYCL_CACHE_PERSISTENT='0';STRATA_VERIFY_DEVICE_PLAN='1';STRATA_VERIFY_NO_HOST='1';STRATA_MIRROR_MIB='61440'};cwd='.';tokenizer=$env:BKIT_TOK;model_name='qwen3.8-flash-next-iq3_s';sampling=[ordered]@{temperature=0.6;top_p=0.95;top_k=20;repetition_penalty=1.05};log='strata-iq3_s-sycl.log';host='127.0.0.1';port=8080}; [IO.File]::WriteAllText((Join-Path (Get-Location).Path 'strata-iq3_s-sycl.json'),($cfg|ConvertTo-Json -Depth 5),(New-Object System.Text.UTF8Encoding $false))"
if errorlevel 1 (
  echo 設定の生成に失敗しました。
  pause
  exit /b 1
)
echo.
echo 設定を生成しました: strata-iq3_s-sycl.json
echo   exe       : %ENGINE%
echo   pack      : %PACKDIR%
echo   native    : %NATIVE%
echo   ple-gguf  : %PLE%
echo   tokenizer : %TOK%
echo.

set /p "GO=BENCH.bat を実行しますか？ [Y/n]: "
if /i "%GO%"=="n" (
  echo 設定だけ作りました。後で BENCH.bat をダブルクリックすればベンチが走ります。
  pause
  exit /b 0
)
call BENCH.bat
pause
endlocal
