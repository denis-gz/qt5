#!/bin/sh

function usage() {
  echo "Usage: $0 <clone|compile|clean>"
}

function clone() {
  # Clone upstream repo and submodules
  git clone https://github.com/qt/qt5.git
  cd qt5
  git checkout v5.6.3
  perl init-repository --module-subset=default,-qtwebengine
  # Switch origin to our repos
  git remote set-url origin https://github.com/denis-gz/qt5.git
  pushd qtbase
  git remote set-url origin https://github.com/denis-gz/qtbase.git
  popd
  # Checkout to branch for in-house build
  git fetch origin in-house
  git checkout in-house
  git submodule update --recursive
  if [ ! -x `basename $0` ]; then
    cp -f ../`basename $0` .
  fi
  echo
  echo You are now in `pwd`.
}

function compile() {
  DEPLOY_PATH=/opt/Qt5/clang_64
  echo
  echo Binaries deploy path: $DEPLOY_PATH
  echo
  if [ ! -f qtbase\tools\configure\Makefile ]; then
    ./configure -prefix $DEPLOY_PATH -developer-build -force-debug-info -opensource -confirm-license -nomake examples -nomake tests -skip qtwebengine
    echo After that, run 'make install' to copy all the stuff to $DEPLOY_PATH.
  else
    echo Run 'make' to build Qt, then run 'make install' to copy all the stuff to $DEPLOY_PATH.
  fi
}

function clean() {
  git clean -ffdx -e "$(basename $0)"
  git submodule foreach "git clean -ffdx"
}

case $1 in
  clone)   clone;;
  compile) compile;;
  clean)   clean;;
  *)       usage;;
esac
