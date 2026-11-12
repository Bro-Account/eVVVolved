#!/bin/bash

# Downloads the official Firebird 5.0.4 Linux tarball and stages the runtime
# tree into deps/firebird-5.0.4-<arch> (the folder the Linux install rules
# copy next to the program as firebird/, where linux_specific/vvv-start.sh
# points FIREBIRD at). Same role as fetch-firebird.sh on macOS and the zip
# kit step in fetch-windows-deps.ps1 on Windows.
#
# Architecture is taken from uname -m (aarch64 -> arm64, x86_64 -> x64);
# override with VVV_ARCH=arm64|x64. Checksum-pinned. Re-running is safe.
#
# Note: the CMakeLists default path is deps/firebird-5.0.4-arm64; on other
# architectures pass -DVVV_FIREBIRD_ROOT=<deps dir> to CMake.

set -euo pipefail

FB_VERSION=5.0.4.1812-0
case "${VVV_ARCH:-$(uname -m)}" in
  aarch64|arm64) FB_ARCH=arm64; FB_SHA256=1a3eb3d46b82e96c784800aeec37287d4c47acec4d8caed6c7897beb4ff6cee0 ;;
  x86_64|x64)    FB_ARCH=x64;   FB_SHA256=ab6a15a0258f38b022be496bb5e038c14e8628ce9acd0f9a06288a3baedd917b ;;
  *) echo "Unsupported architecture: ${VVV_ARCH:-$(uname -m)}" >&2; exit 1 ;;
esac

FB_NAME="Firebird-${FB_VERSION}-linux-${FB_ARCH}.tar.gz"
FB_URL="https://github.com/FirebirdSQL/firebird/releases/download/v5.0.4/${FB_NAME}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEPS="${ROOT}/deps"
DEST="${DEPS}/firebird-5.0.4-${FB_ARCH}"

if [ -f "${DEST}/lib/libfbclient.so" ] || [ -f "${DEST}/lib/"libfbclient.so.* ]; then
  echo "Firebird runtime already staged in ${DEST}"
  exit 0
fi

mkdir -p "${DEPS}"
PKG="${DEPS}/downloads/${FB_NAME}"
mkdir -p "${DEPS}/downloads"
if [ -f "${PKG}" ]; then
  echo "${FB_SHA256}  ${PKG}" | sha256sum -c - >/dev/null
else
  curl -fL --retry 2 -o "${PKG}" "${FB_URL}"
  echo "${FB_SHA256}  ${PKG}" | sha256sum -c -
fi

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

tar -xzf "${PKG}" -C "${TMP}"

# the outer tarball only ships an installer; the runtime tree lives in the
# buildroot.tar.gz next to it
BUILDROOT="$(find "${TMP}" -maxdepth 2 -name buildroot.tar.gz | head -1)"
if [ -z "${BUILDROOT}" ]; then
  echo "Could not find buildroot.tar.gz inside ${FB_NAME}" >&2
  exit 1
fi
mkdir -p "${TMP}/root"
tar -xzf "${BUILDROOT}" -C "${TMP}/root"

# the buildroot carries the runtime as <...>/opt/firebird
FB_DIR="$(find "${TMP}/root" -maxdepth 3 -type d -name firebird -path '*/opt/*' | head -1)"
if [ -z "${FB_DIR}" ]; then
  echo "Could not find the opt/firebird tree inside the buildroot" >&2
  exit 1
fi

mkdir -p "${DEST}"
cp -a "${FB_DIR}/." "${DEST}/"

echo "Firebird ${FB_ARCH} runtime staged in ${DEST}"
echo "Quick check: LD_LIBRARY_PATH=${DEST}/lib ${DEST}/bin/isql -z"
