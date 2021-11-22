#!/bin/sh

function usage() {
  echo "Usage: $0 <clone|compile|clean>"
}

function clone() {
  # Clone upstream repo and submodules
  git clone git@github.com:qt/qt5.git

  cd qt5
  git checkout 5.12.12
  perl init-repository -f --module-subset=essential,qtimageformats,qtgraphicaleffects,qtremoteobjects,qtquickcontrols,qtsvg,qtmacextras,qtwebchannel,qtxmlpatterns

  # Switch origins to forked repos
  pushd qtbase
  git remote set-url origin git@github.com:denis-gz/qtbase.git
  #git fetch origin 5.12.12-itarian
  git checkout 5.12.12-itarian
  popd

  pushd qtdeclarative
  git remote set-url origin git@github.com:denis-gz/qtdeclarative.git
  #git fetch origin 5.12.12-itarian
  git checkout 5.12.12-itarian
  popd

  pushd qtimageformats
  git remote set-url origin git@github.com:denis-gz/qtimageformats.git
  #git fetch origin 5.12.12-itarian
  git checkout 5.12.12-itarian
  popd

  pushd qtremoteobjects
  git remote set-url origin git@github.com:denis-gz/qtremoteobjects.git
  #git fetch origin 5.12.12-itarian
  git checkout 5.12.12-itarian
  popd

  git remote set-url origin git@github.com:denis-gz/qt5.git
  #git fetch origin 5.12.12-itarian
  git checkout 5.12.12-itarian

  if [ ! -x `basename $0` ]; then
    cp -f ../`basename $0` .
  fi
  echo
  echo You are now in `pwd`.
}

function compile() {
  DEPLOY_PATH=/opt/Qt/5.12.12/clang_64
  echo
  echo Binaries deploy path: $DEPLOY_PATH
  echo
  if [ ! -f qtbase\tools\configure\Makefile ]; then
    ./configure -prefix $DEPLOY_PATH -developer-build -optimized-tools -force-debug-info -opensource -confirm-license -nomake examples -skip qtwebengine
    echo "all:\ncheck:\nclean:\ninstall:\n" > qtbase/examples/Makefile
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
