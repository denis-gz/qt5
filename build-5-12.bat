@echo off

::set PATH=C:\Perl64\bin;%PATH%

:check_dev
if "%VisualStudioVersion%" GEQ "15" goto check_git
echo You should run this in VS2017 Native Tools Command Prompt window.
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
if "%1"=="compile" goto compile
if "%1"=="clean" goto clean
echo Usage: %~n0 ^<clone^|compile^|clean^>
exit /b 1

:clone
:: Clone upstream repo and submodules
call git clone https://github.com/qt/qt5.git
cd qt5
call git checkout v5.12.6
perl init-repository --module-subset=default,-qtwebengine
:: Switch origin to our repos
call git remote set-url origin https://github.com/denis-gz/qt5.git
pushd qtbase
call git remote set-url origin https://github.com/denis-gz/qtbase.git
popd
:: Checkout to branch for 5.12.6-itarian build
call git fetch origin 5.12.6-itarian
call git checkout 5.12.6-itarian
call git submodule update --recursive
if not exist %~nx0 copy ..\%~nx0 .
echo.
echo You are now in %CD%.
exit /B 0

:compile
setlocal
for /F "usebackq tokens=2 delims== " %%v in (`type qtbase\.qmake.conf ^| findstr MODULE_VERSION`) do (
  @set MODULE_VERSION=%%v
)
set OPENSSL_INC=C:/Work/openssl-1.1/include
set OPENSSL_LIB=C:/Work/openssl-1.1/lib
set DEPLOY_PATH=C:/Qt/%MODULE_VERSION%/msvc2017

echo.
echo OpenSSL include path: %OPENSSL_INC%
echo Binaries deploy path: %DEPLOY_PATH%
echo.

if not exist qtbase\tools\configure\Makefile (
  call configure -prefix %DEPLOY_PATH% -developer-build -debug-and-release -force-debug-info -opensource -confirm-license -opengl dynamic -openssl-runtime -I %OPENSSL_INC% -L %OPENSSL_LIB% -ltcg -nomake examples -nomake tests -skip qtwebengine -mp -make-tool jom
  echo After that, run `jom install' to copy all the stuff to %DEPLOY_PATH%.
) else (
  echo Run `jom' to build Qt, then run `jom install' to copy all the stuff to %DEPLOY_PATH%.
)
exit /b 0

:clean
call git clean -ffdx -e %~nx0
call git submodule foreach "git clean -ffdx"
exit /B %ERRORLEVEL%
