@echo off
REM The manual pre-step seam, step by step (spec 055 decision 12 / docs/spec.md
REM S12): what a wired `juice build` does in one step is spelled out here as two
REM explicit steps -- (1) the jaix pre-step: transpile the package sources file
REM by file into the target/jaix/ mirror; (2) the ordinary juice build and run.
REM
REM Step 2's juice build re-runs step 1 itself (the package's jaix marker wires
REM the pre-step into build), overwriting the mirror with byte-identical views;
REM running both is harmless by design, and the E2E dual-path test asserts that
REM identity: the mirror after the manual step 1 equals the mirror after the
REM wired pre-step, byte for byte.
REM
REM usage: two-step.bat [transpile-only]
REM   (no argument)   step 1 + step 2 (juice build, then juice run)
REM   transpile-only  step 1 alone -- inspect the mirror before the wired build
REM                   overwrites it
REM
REM jaix resolves through the PATH first (the production posture -- the wired
REM pre-step itself probes PATH for "jaix"; the demo marker keeps its exe field
REM empty), with the sibling jaix-cli dev layout as the fallback. juice resolves
REM to this repository's own build (target/juice.exe) first -- the jaix marker
REM is this repo's feature, so a stale PATH-installed juice would reject the
REM manifest -- and falls back to the PATH lookup.

setlocal
set "ROOT=%~dp0"
cd /d "%ROOT%" || exit /b 1

REM Resolve jaix: the PATH lookup first (the production posture), then the
REM sibling jaix-cli dev layout (%%~fi normalizes the .. components -- cmd's
REM PATH search does not resolve them). When the dev layout wins, its directory
REM joins PATH so the wired pre-step's own PATH probe finds jaix.
REM The flat goto structure avoids delayed expansion: %VAR% references inside a
REM parenthesized block would expand at parse time, before the block runs.
set "JAIX="
for /f "delims=" %%i in ('where jaix 2^>nul') do if not defined JAIX set "JAIX=%%i"
if defined JAIX goto :jaix_resolved
for %%i in ("%ROOT%..\..\..\..\jaix-cli\target\jaix.exe") do set "JAIX=%%~fi"
if not exist "%JAIX%" (
  echo [two-step] jaix not found: put jaix on PATH, or build jaix-cli 1>&2
  exit /b 1
)
for %%i in ("%JAIX%\..") do set "PATH=%%~fi;%PATH%"
:jaix_resolved

REM juice resolves to this repository's own build first (the jaix marker is
REM this repo's feature -- a stale PATH-installed juice would reject the
REM manifest), falling back to the PATH lookup.
set "JUICE="
for %%i in ("%ROOT%..\..\..\target\juice.exe") do set "JUICE=%%~fi"
if exist "%JUICE%" goto :juice_resolved
set "JUICE="
for /f "delims=" %%i in ('where juice 2^>nul') do if not defined JUICE set "JUICE=%%i"
if not defined JUICE (
  echo [two-step] juice not found: build this repo, or put juice on PATH 1>&2
  exit /b 1
)
:juice_resolved

REM Step 1: the manual pre-step. The loop mirrors the wired scan: the package's
REM src/*.jai files, except the juice test block file (jaix cannot parse test
REM blocks without its test block plugin, which the config excludes -- the mixed
REM package seam; calc_tests.jai keeps its own juice path). The config file is
REM jaix's compile-time input, not a transpile input. All paths are absolute:
REM jaix's internal jai #run switches the working directory, so relative
REM arguments would resolve against the wrong directory.
echo [two-step] step 1: jaix pre-step -^> target/jaix/
if not exist "%ROOT%target\jaix\src" mkdir "%ROOT%target\jaix\src"
for %%f in ("%ROOT%src\*.jai") do (
  if /i not "%%~nxf"=="calc_tests.jai" (
    echo [two-step] jaix transpile src\%%~nxf
    "%JAIX%" transpile "%%f" -o "%ROOT%target\jaix\src\%%~nxf" --config "%ROOT%jaix.config.jai"
    if errorlevel 1 exit /b 1
  ) else (
    echo [two-step] skip src\%%~nxf - juice test block file stays out of the mirror
  )
)
call :clean_driver_files
if "%~1"=="transpile-only" exit /b 0

echo [two-step] step 2: juice build
"%JUICE%" build
if errorlevel 1 exit /b 1
REM The wired pre-step's jaix spawns leave driver litter at the package root
REM (the scan cwd). Juice's scans exclude driver litter themselves (dot-prefix
REM naming + content marker), so the next invocation succeeds either way; clean
REM between the two commands to keep the fixture root tidy.
call :clean_driver_files
echo [two-step] step 2: juice run
"%JUICE%" run
if errorlevel 1 exit /b 1
call :clean_driver_files
exit /b 0

REM jaix's CLI driver files land in the working directory (one dot-prefixed
REM .jaix-<hash>.jai per transpile call); the fixture keeps only its two
REM manifests at the root, so every other root-level .jai is disposable driver
REM litter -- the name-unrelated cleanup matches the dot-prefixed names too.
:clean_driver_files
for %%f in ("%ROOT%*.jai") do (
  if /i not "%%~nxf"=="package.jai" if /i not "%%~nxf"=="jaix.config.jai" del "%%f"
)
exit /b 0
