@echo off

setlocal

for /F "usebackq tokens=2,3 delims=. " %%X in (`where /Q python.exe ^&^& python.exe --version 2^>^&1 ^|^| echo 0.0.0`) do set PY_VER=%%X.%%Y
if not "%PY_VER%"=="2.7" set PATH=C:\Python27;%PATH%

where /Q jom.exe || set PATH=C:\Qt\Tools\QtCreator\bin\jom;%PATH%

set LLVM_INSTALL_DIR=D:\Program Files (x86)\LLVM

:check_dev
if "%VisualStudioVersion%" GEQ "16" goto check_git
echo You should run this in VS2019 Native Tools Command Prompt window.
exit /b 1

:check_git
where /Q git && goto check_perl
echo There is no Git in PATH.
exit /b 1

:check_perl
where /Q perl && goto check_jom
echo There is no Perl in PATH.
exit /b 1

:check_jom
where /Q jom && goto check_llvm
echo There is no jom in PATH.
exit /b 1

:check_llvm
if exist "%LLVM_INSTALL_DIR%\bin\libclang.dll" goto check_args
echo There is no LLVM in "%LLVM_INSTALL_DIR%".
exit /b 1

:check_args
if "%1"=="clone"        goto clone
if "%1"=="configure"    goto configure
if "%1"=="compile"      goto compile
if "%1"=="docs"         goto docs
if "%1"=="install"      goto install
if "%1"=="install_docs" goto install_docs
if "%1"=="clean"        goto clean
echo Usage: %~n0 ^<clone^|configure^|compile^|docs^|install^|install_docs^|clean^>
echo.
echo For clone, run this command from upper directory.
exit /b 1

:clone
:: Clone upstream repo and submodules
call git clone https://github.com/qt/qt5.git qt-5.15
cd qt-5.15
call git checkout v5.15.16-lts-lgpl
perl init-repository --force --module-subset=default
:: Switch origin to our repos
call git remote set-url origin https://github.com/denis-gz/qt5.git
pushd qtbase
call git remote set-url origin https://github.com/denis-gz/qtbase.git
popd
pushd qtwebengine
call git remote set-url origin https://github.com/denis-gz/qtwebengine.git
popd
:: Checkout to branch for 5.12.12-itarian build
call git fetch origin 5.15.16-itarian
call git checkout 5.15.16-itarian
call git submodule update --recursive
if not exist %~nx0 copy ..\%~nx0 .
echo.
echo You are now in %CD%.
exit /B 0

:configure
for /F "usebackq tokens=2 delims== " %%v in (`type qtbase\.qmake.conf ^| findstr MODULE_VERSION`) do (
  @set MODULE_VERSION=%%v
)
set OPENSSL_INC=C:/Work/openssl-1.1/include
set OPENSSL_LIB=C:/Work/openssl-1.1/lib
set DEPLOY_PATH=C:/Qt/%MODULE_VERSION%/msvc2019
call configure -recheck-all -prefix %DEPLOY_PATH% -debug-and-release -force-debug-info -opensource -confirm-license -silent -opengl dynamic -openssl-runtime -I %OPENSSL_INC% -L %OPENSSL_LIB% -webengine-proprietary-codecs -ltcg -nomake examples -mp -make-tool jom
exit /B %ERRORLEVEL%

:compile
jom.exe
exit /B %ERRORLEVEL%

:docs
where /Q qmake.exe || set PATH=%CD%\qtbase\bin;%PATH%
where /Q qdoc.exe || set PATH=%CD%\qttools\bin;%PATH%
if not exist "%CD%\qttools\bin\libclang.dll" copy /B "%LLVM_INSTALL_DIR%\bin\libclang.dll" "%CD%\qttools\bin\"
jom.exe qch_docs
exit /B %ERRORLEVEL%

:install
jom.exe install
exit /B %ERRORLEVEL%

:install_docs
jom.exe install_qch_docs
exit /B %ERRORLEVEL%

:clean
call git clean -ffdx -e %~nx0
call git submodule foreach "git clean -ffdx"
exit /B %ERRORLEVEL%
