# folder: src
#         ---

FIND_PACKAGE(wxWidgets REQUIRED html adv core base net aui xrc qa richtext )
INCLUDE(${wxWidgets_USE_FILE})

# The data_interface headers do 'using namespace std;', which makes the C++17
# std::byte clash with the 'byte' typedef in the Windows SDK headers. VVV does
# not use std::byte, so disable it for MSVC.
if(MSVC)
  add_compile_definitions(_HAS_STD_BYTE=0)
endif()

include_directories( ${PROJECT_SOURCE_DIR}/src/ibpp/core
                     ${PROJECT_SOURCE_DIR}/src/data_interface
) 

# look for TagLib
find_path( TAGLIB_INCLUDE_PATH tag.h PATH_SUFFIXES taglib DOC "Path to TagLib header files" )
message( STATUS "TagLib header files path: " ${TAGLIB_INCLUDE_PATH} )
if(WIN32)
  find_file( TAGLIB_LIB_PATH_DEBUG tagd.lib DOC "Path to the DEBUG TagLib library" )
  find_file( TAGLIB_LIB_PATH_RELEASE tag.lib DOC "Path to the RELEASE TagLib library" )
elseif(APPLE)
  # dev builds: Homebrew's shared library, copied into the bundle by MACOSX_fixup_bundle.sh;
  # release builds: the static one from scripts/build-deps-macos.sh
  find_library( TAGLIB_LIB tag )
  if( NOT TAGLIB_LIB )
    message( FATAL_ERROR "Unable to find TagLib" )
  endif( NOT TAGLIB_LIB )
elseif(UNIX)
  # Linux: use the distribution TagLib (shared since Debian 13 / libtag-dev 2.0; the
  # original static libtag.a hunt predates distro packages)
  find_library( TAGLIB_LIB tag PATHS /usr/lib /usr/local/lib )
  if( NOT TAGLIB_LIB )
    message( FATAL_ERROR "Unable to find TagLib" )
  else( NOT TAGLIB_LIB )
    message( STATUS "TagLib: " ${TAGLIB_LIB} )
  endif( NOT TAGLIB_LIB )
else(WIN32)
  find_library( TAGLIB_LIB libtag.a PATHS /usr/lib /usr/local/lib )
  if( NOT TAGLIB_LIB )
    message( FATAL_ERROR "Unable to find TagLib" )
  else( NOT TAGLIB_LIB )
    message( STATUS "TagLib: " ${TAGLIB_LIB} )
  endif( NOT TAGLIB_LIB )
endif(WIN32)

include_directories( ${TAGLIB_INCLUDE_PATH} )
if( TAGLIB_LIB MATCHES "\\.a$" )   # only a static link needs the TAGLIB_STATIC macro
  add_definitions( -DTAGLIB_STATIC )
endif()

if( WIN32 )
  add_definitions( -DIBPP_WINDOWS )
elseif( APPLE )
  add_definitions( -DIBPP_DARWIN )
else( WIN32 )
  add_definitions( -DIBPP_LINUX )
endif( WIN32 )

add_subdirectory( ibpp )
add_subdirectory( data_interface )

link_directories (${PROJECT_BINARY_DIR}/src/ibpp/core
                  ${PROJECT_BINARY_DIR}/src/data_interface
) 


# For convenience we define the sources as a variable. You can add 
# header files and cpp/c files and CMake will sort them out
set( SRCS
  audio_metadata.cpp
  audio_metadata.h
  catalog_volume.cpp
  catalog_volume.h
  catalog_volume_functions.cpp
  catalog_volume_functions.h
  choose_virtual_folder.cpp
  choose_virtual_folder.h
  chooselang.cpp
  chooselang.h
  convert_db_unicode.cpp
  decode_search_string.cpp
  decode_search_string.h
  dlg_file_information.cpp
  dlg_file_information.h
  exportdata.cpp
  exportdata.h
  long_task_beep.cpp
  long_task_beep.h
  mainframe.cpp
  mainframe.h
  mylistitemdata.h
  mytreeitemdata.h
  object_description.cpp
  object_description.h
  opencatalog.cpp
  opencatalog.h
  resource.h
  restore.cpp
  restore.h
  settings.cpp
  settings.h
  update_volume.cpp
  update_volume.h
  utils.cpp
  utils.h
  vvv.cpp
  vvv.h
  window_position.cpp
  window_position.h
)
  

# If we build for windows systems, we also include the resource file
# containing the manifest, icon and other resources
if(WIN32)
  set( SRCS ${SRCS} windows_specific.cpp windows_specific.h vvv.rc vvv.rc2 )
endif(WIN32)

#--------------------------------------------------------------------------------
# For Apple set the icns file containing icons
if(APPLE)
  # icon files to copy in the bundle
  set( OSX_ICON_FILES ${CMAKE_CURRENT_SOURCE_DIR}/graphics/vvv.icns ${CMAKE_CURRENT_SOURCE_DIR}/graphics/vvv-document.icns ) 
  # set where in the bundle to put the icns files
  set_source_files_properties( ${OSX_ICON_FILES} PROPERTIES MACOSX_PACKAGE_LOCATION Resources)
  # include the icns files in the target
  set( SRCS ${SRCS} ${OSX_ICON_FILES} )
ENDIF(APPLE)

add_executable( vvv WIN32 MACOSX_BUNDLE ${SRCS} )
if( WIN32 AND MSVC )
  # vvv.rc embeds the wxWidgets manifest (common controls v6 + DPI awareness),
  # so the linker must not generate a second one.
  target_link_options( vvv PRIVATE /MANIFEST:NO )
endif()
if(APPLE)
  # VVV.app / Contents/MacOS/VVV, as the upstream macOS releases were named
  set_target_properties( vvv PROPERTIES OUTPUT_NAME VVV )
endif(APPLE)

if(APPLE)
  # configure CMake to use a custom Info.plist
  set_target_properties( vvv PROPERTIES MACOSX_BUNDLE_INFO_PLIST ${PROJECT_SOURCE_DIR}/vvv-Info.plist )
ENDIF(APPLE)

if(WIN32)
  target_link_libraries( vvv debug ${TAGLIB_LIB_PATH_DEBUG} optimized ${TAGLIB_LIB_PATH_RELEASE} )
else(WIN32)
  target_link_libraries( vvv ${TAGLIB_LIB} )
endif(WIN32)
target_link_libraries(vvv data_interface ibpp ${wxWidgets_LIBRARIES})
if( APPLE )
  # Firebird 5 runtime extracted from the official pkg by scripts/fetch-firebird.sh (x86_64: deps/fb5-x86_64)
  set( FIREBIRD_ROOT ${PROJECT_SOURCE_DIR}/deps/fb5/Resources CACHE PATH "Firebird 5 Resources folder" )
  find_library( FB_LIB fbclient PATHS ${FIREBIRD_ROOT}/lib NO_DEFAULT_PATH )
  if( NOT FB_LIB )
    message( FATAL_ERROR "Unable to find libfbclient in ${FIREBIRD_ROOT}/lib, run scripts/fetch-firebird.sh" )
  endif( NOT FB_LIB )
  message( STATUS "Firebird interface: " ${FB_LIB} )
  target_link_libraries( vvv ${FB_LIB} )
elseif( UNIX )
  # Linux: prefer a Firebird 5 runtime staged in deps/ (the same pattern the
  # Windows and macOS builds use). Modern Firebird (3+) has no separate fbembed
  # library: the client library (libfbclient) runs the engine in-process when
  # opening local databases, so the runtime folder only matters at run time
  # (see linux_specific/vvv-start.sh).
  set( VVV_FIREBIRD_ROOT "${PROJECT_SOURCE_DIR}/deps/firebird-5.0.4-arm64" CACHE PATH "Firebird runtime folder" )
  find_library( FB_LIB fbclient PATHS ${VVV_FIREBIRD_ROOT}/lib NO_DEFAULT_PATH )
  if( NOT FB_LIB )
    find_library( FB_LIB fbclient PATHS /usr/lib /usr/local/lib /opt/firebird/lib ${PROJECT_SOURCE_DIR}/firebird_runtime/firebird )
  endif()
  if( NOT FB_LIB )
    message( FATAL_ERROR "Unable to find firebird interface" )
  else( NOT FB_LIB )
    message( STATUS "Firebird interface: " ${FB_LIB} )
  endif( NOT FB_LIB )

  # look for the folder containing the firebird embedded files to ship with the program
  find_path( FB_EMBEDDED_PATH firebird.conf ${PROJECT_SOURCE_DIR}/firebird_runtime ${PROJECT_SOURCE_DIR}/../../firebird_embedded_2.0.4_runtime )
  message( STATUS "Embedded firebird files path: " ${FB_EMBEDDED_PATH} )

#  target_link_libraries( vvv -lfbembed )
  target_link_libraries( vvv ${FB_LIB} )
endif()


# installation stuff

install( TARGETS vvv DESTINATION . )

if( APPLE )
  # copy the Firebird 5 runtime (embedded engine = libfbclient + plugins/libEngine13), Resources, not Frameworks: it contains data files; vvv.cpp points FIREBIRD at it
  set( FB_BUNDLE_DIR VVV.app/Contents/Resources/firebird )
  install( DIRECTORY ${FIREBIRD_ROOT}/lib ${FIREBIRD_ROOT}/intl ${FIREBIRD_ROOT}/tzdata
           DESTINATION ${FB_BUNDLE_DIR} USE_SOURCE_PERMISSIONS )
  # only the plugins an embedded connection needs (no sample crypt, UDR, trace, profiler)
  install( FILES ${FIREBIRD_ROOT}/plugins/libEngine13.dylib ${FIREBIRD_ROOT}/plugins/libSrp.dylib ${FIREBIRD_ROOT}/plugins/libLegacy_Auth.dylib
           DESTINATION ${FB_BUNDLE_DIR}/plugins )
  install( FILES ${FIREBIRD_ROOT}/firebird.conf ${FIREBIRD_ROOT}/firebird.msg ${FIREBIRD_ROOT}/plugins.conf
                 ${FIREBIRD_ROOT}/databases.conf ${FIREBIRD_ROOT}/security5.fdb ${FIREBIRD_ROOT}/License.txt
           DESTINATION ${FB_BUNDLE_DIR} )
  # converting catalogs of VVV <= 1.5 (convert-old-catalog.sh): restore with gbak, compare row counts with isql
  install( PROGRAMS ${FIREBIRD_ROOT}/bin/gbak ${FIREBIRD_ROOT}/bin/isql DESTINATION ${FB_BUNDLE_DIR}/bin )
  install( PROGRAMS ${PROJECT_SOURCE_DIR}/osx_specific/convert-old-catalog.sh DESTINATION VVV.app/Contents/Resources )
endif( APPLE )

if( UNIX AND NOT APPLE )
  if( FB_EMBEDDED_PATH )
    # copy the legacy (Firebird 2) embedded runtime, if staged
    install( DIRECTORY ${FB_EMBEDDED_PATH}/ DESTINATION . USE_SOURCE_PERMISSIONS )
  endif()
  if( VVV_FIREBIRD_ROOT )
    # copy the Firebird 5 runtime into the folder linux_specific/vvv-start.sh expects
    install( DIRECTORY ${VVV_FIREBIRD_ROOT}/ DESTINATION firebird USE_SOURCE_PERMISSIONS )
  endif()
  # copy other files used only for the Linux version
  install( FILES ${PROJECT_SOURCE_DIR}/linux_specific/readme.txt
                 ${PROJECT_SOURCE_DIR}/linux_specific/License.txt
                 DESTINATION . )
  install( FILES ${PROJECT_SOURCE_DIR}/linux_specific/vvv-start.sh
                 DESTINATION . PERMISSIONS OWNER_EXECUTE OWNER_WRITE OWNER_READ GROUP_EXECUTE
                                           GROUP_READ WORLD_READ WORLD_EXECUTE )

  # License texts of the program itself (COPYING) and of every third-party
  # component shipped next to the app; same layout as the Windows install.
  file( GLOB VVV_LICENSE_FILES "${PROJECT_SOURCE_DIR}/licenses/*" )
  install( FILES ${VVV_LICENSE_FILES} DESTINATION licenses )
  install( FILES "${PROJECT_SOURCE_DIR}/COPYING" DESTINATION licenses )

  # Old-catalog conversion helper: a Firebird 2.5 (gbak + isql) runtime in a
  # subfolder of the program, used for VVV 1.5 (ODS 11) conversions. The app
  # accepts both layouts: firebird-2.5/<tool> and the bin/ of a Firebird
  # tarball (firebird-2.5/bin/<tool>). Staged from deps/ when present; without
  # it the app shows the "conversion helper is missing" message instead.
  # The arm64 engine is a separate deps/firebird-2.5-arm64 folder, assembled
  # by scripts/fetch-firebird25-arm64.sh (Windows ships its own x64 helper
  # from deps/firebird-2.5, see the WIN32 block).
  set( VVV_FB25_ROOT "${PROJECT_SOURCE_DIR}/deps/firebird-2.5-arm64" CACHE PATH "Firebird 2.5 arm64 conversion helper folder" )
  if( EXISTS "${VVV_FB25_ROOT}" )
    file( GLOB VVV_FB25_FILES "${VVV_FB25_ROOT}/*.conf"
                              "${VVV_FB25_ROOT}/*.msg"
                              "${VVV_FB25_ROOT}/*.txt"
                              "${VVV_FB25_ROOT}/*.fdb" )
    install( FILES ${VVV_FB25_FILES} DESTINATION firebird-2.5 )
    foreach( _dir bin intl lib )
      if( EXISTS "${VVV_FB25_ROOT}/${_dir}" )
        install( DIRECTORY "${VVV_FB25_ROOT}/${_dir}" DESTINATION firebird-2.5 USE_SOURCE_PERMISSIONS )
      endif()
    endforeach()
  endif()
endif( UNIX AND NOT APPLE )

if( UNIX )
  # set the installation path of the executable file and the resources (in OS X they are inside the bundle )
  if( APPLE )
    set( EXECUTABLE_INTALL_PATH VVV.app/Contents/MacOS )
    set( RESOURCES_INTALL_PATH VVV.app/Contents/Resources )
  else( APPLE )
    set( EXECUTABLE_INTALL_PATH . )
    set( RESOURCES_INTALL_PATH . )
  endif( APPLE )

  # copy localization files -- vvv files...
  install( FILES ${PROJECT_SOURCE_DIR}/translations/vvv-bg.mo 
           DESTINATION ${RESOURCES_INTALL_PATH}/languages/bg RENAME vvv.mo )
  install( FILES ${PROJECT_SOURCE_DIR}/translations/vvv-cs.mo 
           DESTINATION ${RESOURCES_INTALL_PATH}/languages/cs RENAME vvv.mo )
  install( FILES ${PROJECT_SOURCE_DIR}/translations/vvv-de.mo 
           DESTINATION ${RESOURCES_INTALL_PATH}/languages/de RENAME vvv.mo )
  install( FILES ${PROJECT_SOURCE_DIR}/translations/vvv-es.mo 
           DESTINATION ${RESOURCES_INTALL_PATH}/languages/es RENAME vvv.mo )
  install( FILES ${PROJECT_SOURCE_DIR}/translations/vvv-fr.mo 
           DESTINATION ${RESOURCES_INTALL_PATH}/languages/fr RENAME vvv.mo )
  install( FILES ${PROJECT_SOURCE_DIR}/translations/vvv-gr.mo 
           DESTINATION ${RESOURCES_INTALL_PATH}/languages/gr RENAME vvv.mo )
  install( FILES ${PROJECT_SOURCE_DIR}/translations/vvv-hr.mo 
           DESTINATION ${RESOURCES_INTALL_PATH}/languages/hr RENAME vvv.mo )
  install( FILES ${PROJECT_SOURCE_DIR}/translations/vvv-hu.mo 
           DESTINATION ${RESOURCES_INTALL_PATH}/languages/hu RENAME vvv.mo )
  install( FILES ${PROJECT_SOURCE_DIR}/translations/vvv-it.mo 
           DESTINATION ${RESOURCES_INTALL_PATH}/languages/it RENAME vvv.mo )
  install( FILES ${PROJECT_SOURCE_DIR}/translations/vvv-ja.mo 
           DESTINATION ${RESOURCES_INTALL_PATH}/languages/ja RENAME vvv.mo )
  install( FILES ${PROJECT_SOURCE_DIR}/translations/vvv-nl.mo 
           DESTINATION ${RESOURCES_INTALL_PATH}/languages/nl RENAME vvv.mo )
  install( FILES ${PROJECT_SOURCE_DIR}/translations/vvv-pl.mo 
           DESTINATION ${RESOURCES_INTALL_PATH}/languages/pl RENAME vvv.mo )
  install( FILES ${PROJECT_SOURCE_DIR}/translations/vvv-pt.mo 
           DESTINATION ${RESOURCES_INTALL_PATH}/languages/pt RENAME vvv.mo )
  install( FILES ${PROJECT_SOURCE_DIR}/translations/vvv-ro.mo 
           DESTINATION ${RESOURCES_INTALL_PATH}/languages/ro RENAME vvv.mo )
  install( FILES ${PROJECT_SOURCE_DIR}/translations/vvv-ru.mo 
           DESTINATION ${RESOURCES_INTALL_PATH}/languages/ru RENAME vvv.mo )
  install( FILES ${PROJECT_SOURCE_DIR}/translations/vvv-sr.mo 
           DESTINATION ${RESOURCES_INTALL_PATH}/languages/sr RENAME vvv.mo )
  install( FILES ${PROJECT_SOURCE_DIR}/translations/vvv-sr@latin.mo 
           DESTINATION ${RESOURCES_INTALL_PATH}/languages/sr@latin RENAME vvv.mo )
  install( FILES ${PROJECT_SOURCE_DIR}/translations/vvv-uk.mo 
           DESTINATION ${RESOURCES_INTALL_PATH}/languages/uk RENAME vvv.mo )
  install( FILES ${PROJECT_SOURCE_DIR}/translations/vvv-zh_TW.mo 
           DESTINATION ${RESOURCES_INTALL_PATH}/languages/zh_TW RENAME vvv.mo )
  install( FILES ${PROJECT_SOURCE_DIR}/translations/vvv-zh_CN.mo 
           DESTINATION ${RESOURCES_INTALL_PATH}/languages/zh_CN RENAME vvv.mo )
# ... wxWidgets files
  install( FILES ${PROJECT_SOURCE_DIR}/translations/cs/wxstd.mo DESTINATION ${RESOURCES_INTALL_PATH}/languages/cs )
  install( FILES ${PROJECT_SOURCE_DIR}/translations/de/wxstd.mo DESTINATION ${RESOURCES_INTALL_PATH}/languages/de )
  install( FILES ${PROJECT_SOURCE_DIR}/translations/es/wxstd.mo DESTINATION ${RESOURCES_INTALL_PATH}/languages/es )
  install( FILES ${PROJECT_SOURCE_DIR}/translations/fr/wxstd.mo DESTINATION ${RESOURCES_INTALL_PATH}/languages/fr )
  install( FILES ${PROJECT_SOURCE_DIR}/translations/hr/wxstd.mo DESTINATION ${RESOURCES_INTALL_PATH}/languages/hr )
  install( FILES ${PROJECT_SOURCE_DIR}/translations/hu/wxstd.mo DESTINATION ${RESOURCES_INTALL_PATH}/languages/hu )
  install( FILES ${PROJECT_SOURCE_DIR}/translations/it/wxstd.mo DESTINATION ${RESOURCES_INTALL_PATH}/languages/it )
  install( FILES ${PROJECT_SOURCE_DIR}/translations/ja/wxstd.mo DESTINATION ${RESOURCES_INTALL_PATH}/languages/ja )
  install( FILES ${PROJECT_SOURCE_DIR}/translations/nl/wxstd.mo DESTINATION ${RESOURCES_INTALL_PATH}/languages/nl )
  install( FILES ${PROJECT_SOURCE_DIR}/translations/pl/wxstd.mo DESTINATION ${RESOURCES_INTALL_PATH}/languages/pl )
  install( FILES ${PROJECT_SOURCE_DIR}/translations/pt/wxstd.mo DESTINATION ${RESOURCES_INTALL_PATH}/languages/pt )
  install( FILES ${PROJECT_SOURCE_DIR}/translations/ro/wxstd.mo DESTINATION ${RESOURCES_INTALL_PATH}/languages/ro )
  install( FILES ${PROJECT_SOURCE_DIR}/translations/ru/wxstd.mo DESTINATION ${RESOURCES_INTALL_PATH}/languages/ru )
  install( FILES ${PROJECT_SOURCE_DIR}/translations/sr/wxstd.mo DESTINATION ${RESOURCES_INTALL_PATH}/languages/sr )
  install( FILES ${PROJECT_SOURCE_DIR}/translations/uk/wxstd.mo DESTINATION ${RESOURCES_INTALL_PATH}/languages/uk )
  install( FILES ${PROJECT_SOURCE_DIR}/translations/zh_CN/wxstd.mo DESTINATION ${RESOURCES_INTALL_PATH}/languages/zh_CN )
  install( FILES ${PROJECT_SOURCE_DIR}/translations/zh_TW/wxstd.mo DESTINATION ${RESOURCES_INTALL_PATH}/languages/zh_TW )

#  install( DIRECTORY ${PROJECT_SOURCE_DIR}/translations/ DESTINATION ${RESOURCES_INTALL_PATH}/languages 
#           FILES_MATCHING PATTERN "*.mo"
#           PATTERN ".svn" EXCLUDE )

  # copy other files to the installation path
  # the macOS build ships a Firebird 5 (ODS 13) copy; Windows/Linux keep the Firebird 2 one
  if( APPLE )
    set( STRUCT_UPDATE_DB ${PROJECT_SOURCE_DIR}/osx_specific/vvv-struct-update.fdb )
  else( APPLE )
    set( STRUCT_UPDATE_DB ${PROJECT_SOURCE_DIR}/vvv-struct-update.fdb )
  endif( APPLE )
  install( FILES ${STRUCT_UPDATE_DB}
                 ${PROJECT_SOURCE_DIR}/VVV.fbk
                 ${PROJECT_SOURCE_DIR}/help/en/vvv.htb
                 DESTINATION ${RESOURCES_INTALL_PATH} )  # Contents/Resources on APPLE, see CUtils::GetDataFilesPath

endif( UNIX )

if( WIN32 )
  # Windows has no install rules yet: the run folder is otherwise assembled by build.ps1.
  # Ship the Firebird 5 embedded runtime, wxWidgets release DLLs and the data files
  # next to vvv.exe (CUtils::GetDataFilesPath() returns the exe folder).
  if( NOT VVV_FIREBIRD_ROOT )
    if( CMAKE_SIZEOF_VOID_P EQUAL 8 )
      set( _vvv_fb_arch x64 )
    else()
      set( _vvv_fb_arch x86 )
    endif()
    set( VVV_FIREBIRD_ROOT "${PROJECT_SOURCE_DIR}/../deps/firebird-5.0.4-${_vvv_fb_arch}" )
  endif()

  file( GLOB VVV_FB_ROOT_FILES
        "${VVV_FIREBIRD_ROOT}/*.dll"
        "${VVV_FIREBIRD_ROOT}/*.conf"
        "${VVV_FIREBIRD_ROOT}/*.msg"
        "${VVV_FIREBIRD_ROOT}/*.dat"
        "${VVV_FIREBIRD_ROOT}/SECURITY5.FDB" )
  install( FILES ${VVV_FB_ROOT_FILES} DESTINATION . )
  install( DIRECTORY "${VVV_FIREBIRD_ROOT}/plugins"
                     "${VVV_FIREBIRD_ROOT}/intl"
                     "${VVV_FIREBIRD_ROOT}/tzdata"
           DESTINATION . )

  # wxWidgets runtime: the prebuilt packages keep release and debug DLLs in the
  # same folder; debug ones have '32ud' in their name.
  file( GLOB VVV_WX_RUNTIME_DLLS "${wxWidgets_LIB_DIR}/*_vc14x*.dll" )
  list( FILTER VVV_WX_RUNTIME_DLLS EXCLUDE REGEX "32ud" )
  install( FILES ${VVV_WX_RUNTIME_DLLS} DESTINATION . )

  # Data files. The structure-update catalog must be the Firebird 5 (ODS 13) one.
  install( FILES "${PROJECT_SOURCE_DIR}/VVV.fbk"
                 "${PROJECT_SOURCE_DIR}/osx_specific/vvv-struct-update.fdb"
                 "${PROJECT_SOURCE_DIR}/help/en/vvv.htb"
           DESTINATION . )

  # Old-catalog conversion helper: a trimmed Firebird 2.5 (gbak + isql) in a
  # subfolder of the program, used by the in-app conversion of VVV 1.5 (ODS 11)
  # catalogs. Staged from deps/ when present; without it the app shows the
  # "helper is missing" message instead of converting.
  set( VVV_FB25_ROOT "${PROJECT_SOURCE_DIR}/../deps/firebird-2.5" CACHE PATH "Firebird 2.5 conversion helper folder" )
  if( EXISTS "${VVV_FB25_ROOT}" )
    file( GLOB VVV_FB25_FILES "${VVV_FB25_ROOT}/*.dll"
                              "${VVV_FB25_ROOT}/*.exe"
                              "${VVV_FB25_ROOT}/*.conf"
                              "${VVV_FB25_ROOT}/*.msg"
                              "${VVV_FB25_ROOT}/*.manifest"
                              "${VVV_FB25_ROOT}/*.txt" )
    install( FILES ${VVV_FB25_FILES} DESTINATION firebird-2.5 )
    if( EXISTS "${VVV_FB25_ROOT}/intl" )
      install( DIRECTORY "${VVV_FB25_ROOT}/intl" DESTINATION firebird-2.5 )
    endif()
  endif()

  # License texts of the program itself (COPYING) and of every redistributed
  # third-party component; see licenses/THIRD-PARTY-LICENSES.md in the source
  file( GLOB VVV_LICENSE_FILES "${PROJECT_SOURCE_DIR}/licenses/*" )
  install( FILES ${VVV_LICENSE_FILES} DESTINATION licenses )
  install( FILES "${PROJECT_SOURCE_DIR}/COPYING" DESTINATION licenses )

  file( GLOB VVV_TRANSLATIONS "${PROJECT_SOURCE_DIR}/translations/vvv-*.mo" )
  foreach( _mo ${VVV_TRANSLATIONS} )
    get_filename_component( _name "${_mo}" NAME_WE )   # vvv-de
    string( SUBSTRING "${_name}" 4 -1 _lang )          # de
    install( FILES "${_mo}" DESTINATION "languages/${_lang}" RENAME vvv.mo )
    if( EXISTS "${PROJECT_SOURCE_DIR}/translations/${_lang}/wxstd.mo" )
      install( FILES "${PROJECT_SOURCE_DIR}/translations/${_lang}/wxstd.mo"
               DESTINATION "languages/${_lang}" )
    endif()
  endforeach()
endif( WIN32 )

if( APPLE )
  # must stay the last install rule: fixes library references, bundles wxWidgets/TagLib, signs
  install( CODE "execute_process( COMMAND ${PROJECT_SOURCE_DIR}/MACOSX_fixup_bundle.sh \"\${CMAKE_INSTALL_PREFIX}/VVV.app\" COMMAND_ERROR_IS_FATAL ANY )" )
endif( APPLE )
