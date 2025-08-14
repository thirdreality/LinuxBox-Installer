cmake_minimum_required(VERSION 3.31)
project(openHAB NONE)

set(CMAKE_INSTALL_LIBDIR "lib")

include(ExternalProject)

option(CONFIG_INCLUDE_OPENHAB_ADDONS
       "Pack openhab addons together which is huge size!!!" OFF)

# Generate all the needed debian package
ExternalProject_Add(
  deb-package
  SOURCE_DIR ${CMAKE_CURRENT_LIST_DIR}/deb-package
  CMAKE_ARGS -DCPACK_ARCHIVE_THREADS:STRING=0
             -DCONFIG_INCLUDE_OPENHAB_ADDONS=${CONFIG_INCLUDE_OPENHAB_ADDONS}
  BUILD_COMMAND ${CMAKE_COMMAND} --build <BINARY_DIR> --target package
  INSTALL_COMMAND ""
  BUILD_ALWAYS ON)

ExternalProject_Get_Property(deb-package BINARY_DIR)

install(
  DIRECTORY ${BINARY_DIR}/R3Archives/
  DESTINATION R3Archives
  COMPONENT openHAB
  PATTERN "_CPack_Packages" EXCLUDE)

set(CPACK_GENERATOR TXZ)
set(CPACK_ARCHIVE_THREADS 0)

include(CPack)
