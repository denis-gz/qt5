@echo off

setlocal

for /F "usebackq tokens=2,3 delims=. " %%X in (`where /Q python.exe ^&^& python.exe --version 2^>^&1 ^|^| echo 0.0.0`) do set PY_VER=%%X.%%Y
if not "%PY_VER%"=="2.7" set PATH=C:\Python27;%PATH%

where /Q jom.exe || set PATH=C:\Qt\Tools\QtCreator\bin\jom;%PATH%

set LLVM_INSTALL_DIR=D:\Program Files (x86)\LLVM
set VCPKG_DIR=C:/Work/vcpkg/installed/x86-windows-static-md
for /F "usebackq tokens=2 delims== " %%v in (`type qtbase\.qmake.conf 2^>nul ^| findstr MODULE_VERSION`) do set MODULE_VERSION=%%v
set DEPLOY_PATH=C:/Qt/%MODULE_VERSION%/msvc2019
:: Qt and its build tools load the external zlib and SQLite DLLs; this must come before Git's 64-bit zlib1.dll
set PATH=%VCPKG_DIR:/=\%\bin;%VCPKG_DIR:/=\%\debug\bin;%PATH%

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
call git checkout v5.15.19-lts-lgpl
perl init-repository --force --module-subset=default
:: Switch origin to our repos
call git remote set-url origin https://github.com/denis-gz/qt5.git
pushd qtbase
call git remote set-url origin https://github.com/denis-gz/qtbase.git
popd
:: Checkout to branch for 5.15.19-itarian build
call git fetch origin 5.15.19-itarian
call git checkout 5.15.19-itarian
call git submodule update --recursive
if not exist %~nx0 copy ..\%~nx0 .
echo.
echo You are now in %CD%.
exit /B 0

:configure
set OPENSSL_INC=C:/Work/openssl-1.1/include
set OPENSSL_LIB=C:/Work/openssl-1.1/lib
:: External zlib (zlibd1.dll for debug, zlib1.dll for release) and SQLite (sqlite3d.dll for debug, sqlite3.dll for release)
set ZLIB_OPTS=-system-zlib ZLIB_INCDIR=%VCPKG_DIR%/include ZLIB_LIBS_DEBUG=%VCPKG_DIR%/debug/lib/zlibd.lib ZLIB_LIBS_RELEASE=%VCPKG_DIR%/lib/zlib.lib
set SQLITE_OPTS=-system-sqlite SQLITE_INCDIR=%VCPKG_DIR%/include SQLITE_LIBS_DEBUG=%VCPKG_DIR%/debug/lib/sqlite3d.lib SQLITE_LIBS_RELEASE=%VCPKG_DIR%/lib/sqlite3.lib
call configure -recheck-all -prefix %DEPLOY_PATH% -debug-and-release -force-debug-info -opensource -confirm-license -silent -opengl dynamic -openssl-runtime -I %OPENSSL_INC% -L %OPENSSL_LIB% %ZLIB_OPTS% %SQLITE_OPTS% -webengine-proprietary-codecs -ltcg -nomake examples -mp -make-tool jom
exit /B %ERRORLEVEL%

:compile
jom.exe
exit /B %ERRORLEVEL%

:docs
:: Modules configured before qttools was built run qdoc, qhelpgenerator and qtattributionsscanner from %DEPLOY_PATH%/bin, so this runs after install
if exist "%DEPLOY_PATH:/=\%\bin\qdoc.exe" goto docs_run
echo Run "%~n0 install" first: the documentation tools run from %DEPLOY_PATH%.
exit /b 1
:docs_run
:: qdoc imports libclang.dll
set PATH=%LLVM_INSTALL_DIR%\bin;%PATH%
jom.exe docs
exit /B %ERRORLEVEL%

:install
jom.exe install
if errorlevel 1 exit /B %ERRORLEVEL%
:: Qt and the QSQLITE plugins need the external zlib and SQLite DLLs at run time
for %%f in (bin\zlib1.dll bin\sqlite3.dll debug\bin\zlibd1.dll debug\bin\sqlite3d.dll) do (
    copy /Y "%VCPKG_DIR:/=\%\%%f" "%DEPLOY_PATH:/=\%\bin\" || exit /B 1
)
:: qdoc imports libclang.dll
copy /Y "%LLVM_INSTALL_DIR%\bin\libclang.dll" "%DEPLOY_PATH:/=\%\bin\" || exit /B 1
exit /B 0

:install_docs
jom.exe install_qch_docs
exit /B %ERRORLEVEL%

:clean
call git clean -ffdx -e %~nx0
call git submodule foreach "git clean -ffdx"
exit /B %ERRORLEVEL%
