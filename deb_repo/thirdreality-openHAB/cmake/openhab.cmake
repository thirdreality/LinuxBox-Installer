file(DOWNLOAD
     https://cdn.azul.com/zulu/bin/zulu21.44.17-ca-jdk21.0.8-linux_arm64.deb
     ${CMAKE_CURRENT_BINARY_DIR}/R3Archives/jdk21.0.8-linux_arm64.deb)

file(
  DOWNLOAD
  http://http.us.debian.org/debian/pool/main/libx/libxi/libxi6_1.8-1+b1_arm64.deb
  ${CMAKE_CURRENT_BINARY_DIR}/R3Archives/libxi6_1.8-1+b1_arm64.deb)

file(
  DOWNLOAD
  http://http.us.debian.org/debian/pool/main/libx/libxtst/libxtst6_1.2.3-1.1_arm64.deb
  ${CMAKE_CURRENT_BINARY_DIR}/R3Archives/libxtst6_1.2.3-1.1_arm64.deb)

file(DOWNLOAD
     http://http.us.debian.org/debian/pool/main/x/xorg/x11-common_7.7+23_all.deb
     ${CMAKE_CURRENT_BINARY_DIR}/R3Archives/x11-common_7.7+23_all.deb)

file(
  DOWNLOAD
  http://http.us.debian.org/debian/pool/main/j/java-common/java-common_0.74_all.deb
  ${CMAKE_CURRENT_BINARY_DIR}/R3Archives/java-common_0.74_all.deb)

# @todo make this optional, which is huge
if(CONFIG_INCLUDE_OPENHAB_ADDONS)
  file(
    DOWNLOAD
    https://github.com/openhab/openhab-distro/releases/download/${CONFIG_OPENHAB_VERSION}/openhab-addons-${CONFIG_OPENHAB_VERSION}.kar
    ${CMAKE_CURRENT_BINARY_DIR}/openhab-addons-${CONFIG_OPENHAB_VERSION}.kar)

  install(
    FILES ${CMAKE_BINARY_DIR}/openhab-addons-${CONFIG_OPENHAB_VERSION}.kar
    DESTINATION /opt/openhab/addons
    COMPONENT openhab)
endif()

ExternalProject_Add(
  openhab
  URL https://github.com/openhab/openhab-distro/releases/download/${CONFIG_OPENHAB_VERSION}/openhab-${CONFIG_OPENHAB_VERSION}.zip
  CONFIGURE_COMMAND ""
  BUILD_COMMAND ""
  INSTALL_COMMAND "")

ExternalProject_Get_Property(openhab SOURCE_DIR)

install(
  DIRECTORY ${SOURCE_DIR}/
  DESTINATION /opt/openhab
  USE_SOURCE_PERMISSIONS
  COMPONENT openhab)

configure_file(${CMAKE_CURRENT_LIST_DIR}/openhab/openhab.service.in
               ${CMAKE_CURRENT_BINARY_DIR}/openhab/openhab.service @ONLY)
install(
  FILES ${CMAKE_CURRENT_BINARY_DIR}/openhab/openhab.service
  DESTINATION /usr/lib/systemd/system
  COMPONENT openhab)

set(CPACK_DEBIAN_OPENHAB_PACKAGE_DEPENDS "zulu-21")
set(CPACK_DEBIAN_OPENHAB_PACKAGE_CONTROL_EXTRA
    ${CMAKE_CURRENT_LIST_DIR}/openhab/postinst
    ${CMAKE_CURRENT_LIST_DIR}/openhab/postrm
    ${CMAKE_CURRENT_LIST_DIR}/openhab/prerm)
