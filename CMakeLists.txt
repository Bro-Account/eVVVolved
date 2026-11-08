# The name of our project is "VVV". CMakeLists files in this project can
# refer to the root source directory of the project as ${VVV_SOURCE_DIR} and
# to the root binary directory of the project as ${VVV_BINARY_DIR}.
cmake_minimum_required (VERSION 3.20)
if(APPLE AND NOT CMAKE_OSX_ARCHITECTURES)
  set( CMAKE_OSX_ARCHITECTURES arm64 CACHE STRING "" )
endif()
project (VVV)

set( CMAKE_CXX_STANDARD 17 )
set( CMAKE_CXX_STANDARD_REQUIRED ON )

add_subdirectory( src ) 

# Keep these in sync with CUtils::applicationVersion (src/utils.cpp) and the
# version resource in src/vvv.rc.
set( CPACK_PACKAGE_VERSION_MAJOR 2 )
set( CPACK_PACKAGE_VERSION_MINOR 0 )
set( CPACK_PACKAGE_VERSION_PATCH 0 )
# CPack builds CPACK_PACKAGE_VERSION from major/minor/patch only, so set the
# full four-part version explicitly to match the application.
set( CPACK_PACKAGE_VERSION "2.0.0.0" )
set( CPACK_STRIP_FILES TRUE )
include( CPack )
