#!/bin/sh

# change the current directory to the one that contains this script
# this is needed to run the script from a launcher, a menu entry or similar
cd "$(dirname "$0")"

# with a bundled Firebird 5 runtime (see src/CMakeLists.txt, install rules):
# the client library *and* the embedded engine (plugins/libEngine13.so,
# firebird.msg, intl) must come from the same runtime folder
if [ -d ./firebird/lib ]; then
  export LD_LIBRARY_PATH="$PWD/firebird/lib"
  export FIREBIRD="$PWD/firebird"
else
  export LD_LIBRARY_PATH=./firebird
  export FIREBIRD=.
fi
exec ./vvv

