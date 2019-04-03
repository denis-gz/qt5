@echo off

::set PATH=C:\Perl64\bin;%PATH%

:check_dev
if "%VisualStudioVersion%" GEQ "14" goto check_git
echo You should run this from VS2015 Developer Command Prompt window.
exit /b 1

:check_git
where git >nul 2>&1 && goto check_perl
echo There is no Git in PATH.
exit /b 1

:check_perl
where perl >nul 2>&1 && perl --version|findstr "ActiveState" >nul 2>&1 && goto check_args
echo There is no Perl in PATH (Perl from Cygwin won't do, use ActivePerl).
exit /b 1

:check_args
if "%1"=="clone" goto clone
if "%1"=="debug" goto build
if "%1"=="release" goto build
if "%1"=="clean" goto clean
echo Usage: %~n0 ^<clone^|debug^|release^|clean^>
exit /b 1

:clone
:: Clone upstream repo and submodules
call git clone https://github.com/qt/qt5.git
cd qt5
call git checkout v5.6.3
perl init-repository --module-subset=default,-qtwebengine
:: Switch origin to our repos
call git remote set-url origin https://github.com/denis-gz/qt5.git
pushd qtbase
call git remote set-url origin https://github.com/denis-gz/qtbase.git
popd
:: Checkout to branch for in-house build
call git fetch origin in-house
call git checkout -f in-house
call git pull --recurse-submodules
if not exist %~nx0 copy ..\%~nx0 .
echo.
echo You are now in %CD%.
exit /B 0

:build
setlocal
set BUILD_TYPE=%1
set OPENSSL_INC=C:\Work\openssl-%BUILD_TYPE%\include
set DEPLOY_PATH=C:\Qt5\msvc2015
if "%1"=="release" set BUILD_OPTS=-ltcg

echo.
echo Build type: %BUILD_TYPE%
echo OpenSSL include path: %OPENSSL_INC%
echo Binaries deploy path: %DEPLOY_PATH%
echo.

if not exist qtbase\tools\configure\Makefile (
  call configure -prefix %DEPLOY_PATH% -developer-build %BUILD_OPTS% -%BUILD_TYPE% -force-debug-info -opensource -confirm-license -target xp -opengl dynamic -openssl -I %OPENSSL_INC% -no-cetest -nomake examples -nomake tests -skip qtwebengine -mp -make-tool jom
  echo After that, run `jom install' to copy all the stuff to %DEPLOY_PATH%.
) else (
  echo Run `jom' to build Qt, then run `jom install' to copy all the stuff to %DEPLOY_PATH%.
)
exit /b 0

:clean
call git clean -ffdx -e %~nx0
call git submodule foreach "git clean -ffdx"
exit /B %ERRORLEVEL%
