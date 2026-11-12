#!/bin/bash

# Provisions the Linux build dependencies, the counterpart of
# scripts/fetch-windows-deps.ps1 (Windows) and the deps steps of
# scripts/fetch-firebird.sh (macOS), so that a fresh checkout can be built
# with plain CMake:
#
#   toolchain + wxWidgets  - distribution packages (apt: cmake, g++,
#                            libwxgtk3.2-dev; libtommath1 for the bundled
#                            Firebird client)
#   TagLib         2.3.1   - built from source into /usr/local when the
#                            system TagLib is older than 2.0 (the code is
#                            developed against TagLib 2)
#   Firebird       5.0.4   - official Linux tarball into
#                            deps/firebird-5.0.4-<arch> (fetch-firebird5-linux.sh)
#   Firebird       2.5.3   - old-catalog conversion helper, native arm64/amd64
#                            packages of Debian 8 into deps/firebird-2.5-<arch>
#                            (fetch-firebird25.sh)
#
# Every step is skipped when its target already looks complete, so the script
# is safe to re-run. Set SKIP_WX=1 / SKIP_TAGLIB=1 / SKIP_FIREBIRD5=1 /
# SKIP_FIREBIRD25=1 to leave out individual steps.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ARCH="$(uname -m)"

SUDO=""
if [ "$(id -u)" != "0" ] && command -v sudo >/dev/null; then
  SUDO="sudo"
fi

# --- toolchain, wxWidgets, runtime libs --------------------------------------
if [ "${SKIP_WX:-0}" != "1" ]; then
  echo "Installing toolchain and wxWidgets (apt) ..."
  $SUDO apt-get update -qq
  $SUDO apt-get install -y -qq build-essential cmake pkg-config \
    libwxgtk3.2-dev libtommath1 zlib1g-dev >/dev/null
else
  echo "Skipping wx/toolchain (SKIP_WX=1)"
fi

# --- TagLib ------------------------------------------------------------------
if [ "${SKIP_TAGLIB:-0}" != "1" ]; then
  TL_VERSION=2.3.1
  TL_SHA256='a19d90e6fd41d09a0281ec0fe762d51491d7a6ccffc923c4f7868c5e647ca230'
  TL_URL="https://github.com/taglib/taglib/releases/download/v${TL_VERSION}/taglib-${TL_VERSION}.tar.gz"
  tl_version_found="$(pkg-config --modversion taglib 2>/dev/null || echo 0)"
  if [ "$(printf '%s\n%s\n' "2.0" "${tl_version_found}" | sort -V | head -1)" = "2.0" ]; then
    echo "TagLib ${tl_version_found} found (>= 2.0), skipping the source build"
  elif [ -f /usr/local/include/taglib/tag.h ]; then
    echo "TagLib already installed in /usr/local, skipping"
  else
    echo "Building TagLib ${TL_VERSION} from source into /usr/local ..."
    DL="${ROOT}/deps/downloads"
    mkdir -p "${DL}"
    [ -f "${DL}/taglib-${TL_VERSION}.tar.gz" ] ||
      curl -fL --retry 2 -o "${DL}/taglib-${TL_VERSION}.tar.gz" "${TL_URL}"
    echo "${TL_SHA256}  ${DL}/taglib-${TL_VERSION}.tar.gz" | sha256sum -c - >/dev/null
    TMP="$(mktemp -d)"
    trap 'rm -rf "${TMP}"' EXIT
    tar -xzf "${DL}/taglib-${TL_VERSION}.tar.gz" -C "${TMP}"
    cmake -S "${TMP}/taglib-${TL_VERSION}" -B "${TMP}/build" \
      -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=ON >/dev/null
    cmake --build "${TMP}/build" -j"$(nproc)" >/dev/null
    $SUDO cmake --install "${TMP}/build" >/dev/null
    $SUDO ldconfig
  fi
else
  echo "Skipping TagLib (SKIP_TAGLIB=1)"
fi

# --- Firebird 5 runtime ------------------------------------------------------
if [ "${SKIP_FIREBIRD5:-0}" != "1" ]; then
  "${ROOT}/scripts/fetch-firebird5-linux.sh"
else
  echo "Skipping Firebird 5 runtime (SKIP_FIREBIRD5=1)"
fi

# --- Firebird 2.5 conversion helper ------------------------------------------
if [ "${SKIP_FIREBIRD25:-0}" != "1" ]; then
  "${ROOT}/scripts/fetch-firebird25.sh"
else
  echo "Skipping Firebird 2.5 helper (SKIP_FIREBIRD25=1)"
fi

echo "Linux deps ready."
