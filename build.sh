#!/bin/bash
#
# Builds in-house Qt 5.15 for macOS as universal (x86_64 + arm64) binaries.
#
# Universal output comes from qtbase's 5.15.19-itarian branch, which sets
# QMAKE_APPLE_DEVICE_ARCHS = x86_64 arm64 in mkspecs/common/macx.conf and builds
# qmake itself for both archs; it is also passed to configure below.
#
# Qt WebEngine is built separately, release only, against the staged Qt: its
# universal build (Chromium built per arch, then merged with lipo) refuses debug
# configurations, while the rest of Qt is built debug-and-release, and in a
# top-level build modules cannot be configured differently.
#
# Qt WebEngine is optional: pass --webengine to clone (fetches its sources) and to all.
# Full build: configure, compile, stage, [webengine], package (or just: all [--webengine]).

set -e

QT_TAG=v5.15.19-lts-lgpl
ITARIAN_BRANCH=5.15.19-itarian
MODULE_SUBSET=essential,qtimageformats,qtgraphicaleffects,qtremoteobjects,qtquickcontrols,qtsvg,qtmacextras,qtwebchannel,qtxmlpatterns
ARCHS="x86_64 arm64"

SCRIPT=$(basename "$0")
JOBS=$(sysctl -n hw.ncpu)
MODULE_VERSION=$(sed -n 's/^MODULE_VERSION *= *//p' qtbase/.qmake.conf 2>/dev/null || true)
DEPLOY_PATH=/opt/Qt/$MODULE_VERSION/clang_64
VERSION_DIR=$(dirname "${DEPLOY_PATH#/}")
STAGE_DIR=$PWD/stage
STAGE_PREFIX=$STAGE_DIR$DEPLOY_PATH
PACKAGE=Qt-$MODULE_VERSION-clang_64.tar.bz2

# Must be outside of this directory: anything below it is treated as part of the top-level build
WEBENGINE_BUILD_DIR=$(dirname "$PWD")/$(basename "$PWD")-webengine
# Qt WebEngine: release only (no _debug binaries; debug apps link the release frameworks)
# and without debug info, as Chromium's would only stay in the build tree on macOS anyway.
WEBENGINE_QMAKE_ARGS=(
  CONFIG+=release
  CONFIG-=force_debug_info
  "QT.global.enabled_features-=debug_and_release build_all"
  "QT.global.disabled_features+=debug_and_release build_all"
  --
  -webengine-proprietary-codecs
)
# Node.js is required by Qt WebEngine (keg-only Homebrew formula: brew install node@22)
NODE_DIR=/opt/homebrew/opt/node@22/bin
# Chromium compile jobs; each can take 1+ GB of RAM
WEBENGINE_JOBS=${WEBENGINE_JOBS:-6}

usage() {
  echo "Usage: $SCRIPT <clone|configure|compile|stage|webengine|package|all|install|clean> [--webengine]"
  echo
  echo "  clone      Clone sources into ./qt-5.15 (run from the upper directory)"
  echo "             --webengine: also clone Qt WebEngine with Chromium"
  echo "  configure  Configure for $DEPLOY_PATH"
  echo "  compile    Build Qt, except Qt WebEngine"
  echo "  stage      Install Qt into ./stage"
  echo "  webengine  Build Qt WebEngine against the staged Qt and install it there (takes many hours)"
  echo "  package    Pack ./stage as ../$PACKAGE"
  echo "  all        configure, compile, stage, package"
  echo "             --webengine: also build Qt WebEngine before packaging"
  echo "  install    Copy ./stage to $DEPLOY_PATH (needs sudo)"
  echo "  clean      Remove all build output"
}

check_tools() {
  xcode-select -p >/dev/null 2>&1 || { echo "There is no Xcode selected (xcode-select)."; exit 1; }
  command -v git  >/dev/null || { echo "There is no Git in PATH.";  exit 1; }
  command -v perl >/dev/null || { echo "There is no Perl in PATH."; exit 1; }
}

check_tree() {
  if [ -z "$MODULE_VERSION" ]; then
    echo "Run this from the Qt source root (qtbase/.qmake.conf not found)."
    exit 1
  fi
}

check_stage() {
  [ -x "$STAGE_PREFIX/bin/qmake" ] || { echo "Run \"$SCRIPT stage\" first."; exit 1; }
}

# In-house fixes for submodules that are not forked; applied once, kept in the working tree
apply_patches() {
  local repo=$1 dir=$PWD/$2 patch
  for patch in "$dir"/*.patch; do
    [ -f "$patch" ] || continue
    if git -C "$repo" apply --reverse --check "$patch" 2>/dev/null; then
      continue
    fi
    echo "Applying $(basename "$patch")"
    git -C "$repo" apply "$patch"
  done
}

cmd_clone() {
  # Clone upstream repo and submodules
  git clone https://github.com/qt/qt5.git qt-5.15
  cd qt-5.15
  git checkout $QT_TAG
  local subset=$MODULE_SUBSET
  [ "$WITH_WEBENGINE" = 1 ] && subset=$subset,qtwebengine
  perl init-repository --force --module-subset=$subset
  # Switch origin to our repos
  git remote set-url origin https://github.com/denis-gz/qt5.git
  (cd qtbase && git remote set-url origin https://github.com/denis-gz/qtbase.git)
  # Checkout to branch for $ITARIAN_BRANCH build
  git fetch origin $ITARIAN_BRANCH
  git checkout -B $ITARIAN_BRANCH FETCH_HEAD
  git submodule update --recursive
  [ -f "$SCRIPT" ] || cp "../$SCRIPT" .
  echo
  echo "You are now in $PWD."
}

cmd_configure() {
  check_tree
  echo
  echo "Binaries deploy path: $DEPLOY_PATH"
  echo
  ./configure -recheck-all -prefix "$DEPLOY_PATH" -debug-and-release -force-debug-info -optimized-tools \
    -opensource -confirm-license -nomake examples -nomake tests -skip qtwebengine \
    QMAKE_APPLE_DEVICE_ARCHS="$ARCHS"
}

cmd_compile() {
  check_tree
  make -j$JOBS
}

cmd_stage() {
  check_tree
  rm -rf "$STAGE_DIR"
  # Serial: debug and release sub-makes install some of the same files (e.g. plugins.qmltypes)
  make install INSTALL_ROOT="$STAGE_DIR"
}

cmd_webengine() {
  check_tree
  check_stage
  [ -f qtwebengine/src/3rdparty/chromium/BUILD.gn ] ||
    { echo "There are no Qt WebEngine sources (use \"$SCRIPT clone --webengine\")."; exit 1; }
  [ -x "$NODE_DIR/node" ] || { echo "There is no Node.js in $NODE_DIR (brew install node@22)."; exit 1; }
  command -v python3 >/dev/null || { echo "There is no Python 3 in PATH."; exit 1; }
  python3 -c "import html5lib" 2>/dev/null || { echo "Chromium needs html5lib (python3 -m pip install --user html5lib)."; exit 1; }
  apply_patches qtwebengine/src/3rdparty patches/qtwebengine-chromium
  # depot_tools' ninja is only a wrapper and breaks Chromium's build; WebEngine builds its own ninja
  PATH=$(echo "$PATH" | tr ':' '\n' | grep -v depot_tools | paste -sd: -)
  export PATH="$NODE_DIR:$PATH"
  export NINJAJOBS=-j$WEBENGINE_JOBS

  mkdir -p "$WEBENGINE_BUILD_DIR"
  cd "$WEBENGINE_BUILD_DIR"
  # Build against (and install into) the staged Qt; all its rpaths are relative
  printf '[Paths]\nPrefix=%s\n' "$STAGE_PREFIX" > qt.conf
  QMAKE=("$STAGE_PREFIX/bin/qmake" -qtconf "$PWD/qt.conf")
  if [ ! -f Makefile ]; then
    "${QMAKE[@]}" "$OLDPWD/qtwebengine/qtwebengine.pro" "${WEBENGINE_QMAKE_ARGS[@]}" 2>&1 | tee configure.out
    if ! grep -qE 'Support Qt WebEngine (Qml|Widgets) [. ]+ yes' configure.out; then
      rm -f Makefile
      echo "Qt WebEngine Core is not going to be built, see $PWD/configure.out and config.log"
      exit 1
    fi
  fi
  # Serial on this level, so the two per-arch Chromium builds (ninja, NINJAJOBS each) do not run at once
  make
  make install
  cd "$OLDPWD"
}

cmd_all() {
  cmd_configure
  cmd_compile
  cmd_stage
  [ "$WITH_WEBENGINE" = 1 ] && cmd_webengine
  cmd_package
}

cmd_package() {
  check_tree
  check_stage
  # Same layout as the earlier distributions: opt/Qt/<version>/clang_64, owned by root:wheel
  tar -cjf "../$PACKAGE" -C "$STAGE_DIR" --uid 0 --gid 0 --uname root --gname wheel \
    --options bzip2:compression-level=9 "$VERSION_DIR"
  echo
  echo "Created $(cd .. && pwd)/$PACKAGE"
  echo "To deploy: sudo tar -xjf $PACKAGE -C /"
}

cmd_install() {
  check_tree
  check_stage
  mkdir -p "/$VERSION_DIR"
  ditto "$STAGE_DIR/$VERSION_DIR" "/$VERSION_DIR"
}

cmd_clean() {
  git clean -ffdx -e "$SCRIPT"
  git submodule foreach --recursive "git clean -ffdx"
  rm -rf "$WEBENGINE_BUILD_DIR"
}

WITH_WEBENGINE=0
[ "$2" = --webengine ] && WITH_WEBENGINE=1

check_tools
case $1 in
  clone)     cmd_clone;;
  configure) cmd_configure;;
  compile)   cmd_compile;;
  stage)     cmd_stage;;
  webengine) cmd_webengine;;
  package)   cmd_package;;
  all)       cmd_all;;
  install)   cmd_install;;
  clean)     cmd_clean;;
  *)         usage; exit 1;;
esac
