@echo off
setlocal EnableDelayedExpansion
title Strata PR3607 B60 test
cd /d %~dp0

rem ============================================================
rem  本家 Strata PR #3607 (strata 0.1.60.1) Windows SYCL 実機テスト
rem  このファイルを strata.exe と同じフォルダに置いて実行する
rem ============================================================

set "ENGINE=%~dp0strata.exe"
if not exist "%ENGINE%" (
  echo strata.exe がこのフォルダに見つかりません。
  set /p "ENGDIR=パッケージフォルダ（strata.exe のある場所）を入力してください: "
  if defined ENGDIR set "ENGDIR=!ENGDIR:"=!"
  set "ENGINE=!ENGDIR!\strata.exe"
  if not exist "!ENGINE!" (
    echo 見つかりませんでした: !ENGINE!
    pause
    exit /b 1
  )
)

echo ============================================================
echo  Strata PR #3607 Windows SYCL テスト
echo ============================================================
"%ENGINE%" --version
echo.

rem ---------- GGUF（パック）フォルダを聞く ----------
set /p "PACK=GGUF（パック）のフォルダを入力してください（エクスプローラからドラッグ＆ドロップ可）: "
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
echo   native : %NATIVE%
echo   ple    : %PLE%

rem ---------- MTP（任意） ----------
echo.
set /p "MTPD=MTP のフォルダ（無ければそのまま Enter）: "
if defined MTPD set "MTPD=%MTPD:"=%"
set "MTPARG="
if not "%MTPD%"=="" set "MTPARG=--mtp "%MTPD%""

rem ---------- 環境変数（この3つ＋ミラーが要点） ----------
set SYCL_CACHE_PERSISTENT=0
set STRATA_VERIFY_DEVICE_PLAN=1
set STRATA_VERIFY_NO_HOST=1
set STRATA_MIRROR_MIB=61440

set "ARGS=--pack "%PACK%" --native "%PACK%\%NATIVE%" --ple-gguf "%PACK%\%PLE%" --stream-experts --expert-cache auto --prefill auto --spec 4 --spec-min-p 0.5 --max-context 8192 --tokens 1,2,3 --max-new 128 --greedy --stats %MTPARG%"

set RUNNO=0
:RUN
set /a RUNNO+=1
echo.
echo ============================================================
echo  RUN %RUNNO%  %DATE% %TIME%
echo  "%ENGINE%" %ARGS%
echo ============================================================
"%ENGINE%" %ARGS%
set EC=%ERRORLEVEL%
echo.
echo ===== RUN %RUNNO% 終了（終了コード %EC%） =====
if %RUNNO%==1 (
  echo 初回はエキスパート配置の学習が入るため、2回目の数値が本命です。
  set /p "AGAIN=同じ条件でもう一度回しますか？ [Y/n]: "
  if /i not "!AGAIN!"=="n" goto RUN
)

echo.
echo お疲れさまでした。
echo この画面の出力（特に --stats の内訳・ms/token と、エラーが出た場合はその全文）を
echo コピーして Muse に貼ってください。
pause
endlocal
