cmake_minimum_required(VERSION 3.31)
project(openHAB NONE)

set(CMAKE_INSTALL_LIBDIR "lib")

set(CPACK_GENERATOR DEB)
set(CPACK_DEB_COMPONENT_INSTALL ON)
set(CPACK_DEBIAN_PACKAGE_ARCHITECTURE arm64)
set(CPACK_DEBIAN_ENABLE_COMPONENT_DEPENDS ON)
set(CPACK_DEBIAN_PACKAGE_MAINTAINER "support@3reality.com")
set(CPACK_PACKAGE_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/R3Archives)
set(CPACK_COMPONENTS_ALL zigbee2mqtt node openhab)

find_program(pnpm REQUIRED NAMES pnpm)

include(${CMAKE_CURRENT_LIST_DIR}/cmake/zigbee2mqtt.cmake)
include(${CMAKE_CURRENT_LIST_DIR}/cmake/node.cmake)
include(${CMAKE_CURRENT_LIST_DIR}/cmake/openHAB.cmake)

include(CPack)
