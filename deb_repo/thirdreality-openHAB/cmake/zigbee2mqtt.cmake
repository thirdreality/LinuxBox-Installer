include(ExternalProject)
include(GNUInstallDirs)

ExternalProject_Add(
  zigbee-herdsman
  GIT_REPOSITORY https://github.com/fangzheli/zigbee-herdsman.git
  GIT_TAG 03350c74e565696b25c70f6a00366d9f84c8a5b9
  GIT_SHALLOW ON
  GIT_PROGRESS ON
  SOURCE_DIR ${CMAKE_CURRENT_BINARY_DIR}/zigbee2mqtt/zigbee-herdsman
  CONFIGURE_COMMAND ""
  BUILD_COMMAND
    cd <SOURCE_DIR> && export SOURCE_DIR=<SOURCE_DIR> BINARY_DIR=<BINARY_DIR> &&
    bash ${CMAKE_CURRENT_LIST_DIR}/zigbee2mqtt/build.sh
  INSTALL_COMMAND "")

ExternalProject_Add(
  zigbee2mqtt
  GIT_REPOSITORY https://github.com/fangzheli/zigbee2mqtt.git
  GIT_TAG b4b2dc241978b1bf739d99e00ea873dd63e2d10a
  GIT_SHALLOW ON
  GIT_PROGRESS ON
  SOURCE_DIR ${CMAKE_CURRENT_BINARY_DIR}/zigbee2mqtt/zigbee2mqtt
  CONFIGURE_COMMAND
    rm -rf <BINARY_DIR>/pruned && cp
    ${CMAKE_CURRENT_LIST_DIR}/zigbee2mqtt/pnpm-workspace.yaml <SOURCE_DIR>/
  BUILD_COMMAND
    cd <SOURCE_DIR> && export SOURCE_DIR=<SOURCE_DIR> BINARY_DIR=<BINARY_DIR> &&
    bash ${CMAKE_CURRENT_LIST_DIR}/zigbee2mqtt/build.sh deploy
  INSTALL_COMMAND ""
  DEPENDS zigbee-herdsman)

ExternalProject_Get_Property(zigbee2mqtt BINARY_DIR)

install(
  DIRECTORY ${BINARY_DIR}/pruned/
  DESTINATION /opt/zigbee2mqtt
  COMPONENT zigbee2mqtt
  PATTERN .git EXCLUDE
  PATTERN .github EXCLUDE)
install(
  FILES ${CMAKE_CURRENT_LIST_DIR}/zigbee2mqtt/zigbee2mqtt.service
  DESTINATION /usr/lib/systemd/system
  COMPONENT zigbee2mqtt)

configure_file(${CMAKE_CURRENT_LIST_DIR}/zigbee2mqtt/configuration.yaml.in
               ${CMAKE_CURRENT_BINARY_DIR}/zigbee2mqtt/configuration.yaml @ONLY)
install(
  FILES ${CMAKE_CURRENT_BINARY_DIR}/zigbee2mqtt/configuration.yaml
  DESTINATION /opt/zigbee2mqtt/data
  COMPONENT zigbee2mqtt)

file(
  DOWNLOAD
  http://http.us.debian.org/debian/pool/main/m/mosquitto/mosquitto_2.0.11-1.2+deb12u1_arm64.deb
  ${CMAKE_CURRENT_BINARY_DIR}/R3Archives/mosquitto_2.0.11-1.2+deb12u1_arm64.deb)

file(
  DOWNLOAD
  http://http.us.debian.org/debian/pool/main/d/dlt-daemon/libdlt2_2.18.8-6_arm64.deb
  ${CMAKE_CURRENT_BINARY_DIR}/R3Archives/libdlt2_2.18.8-6_arm64.deb)

file(
  DOWNLOAD
  http://http.us.debian.org/debian/pool/main/m/mosquitto/libmosquitto1_2.0.11-1.2+deb12u1_arm64.deb
  ${CMAKE_CURRENT_BINARY_DIR}/R3Archives/libmosquitto1_2.0.11-1.2+deb12u1_arm64.deb
)

set(CPACK_DEBIAN_ZIGBEE2MQTT_PACKAGE_DEPENDS "openhab-node")
set(CPACK_DEBIAN_ZIGBEE2MQTT_PACKAGE_SECTION javascript)
set(CPACK_DEBIAN_ZIGBEE2MQTT_PACKAGE_CONTROL_EXTRA
    ${CMAKE_CURRENT_LIST_DIR}/zigbee2mqtt/postinst
    ${CMAKE_CURRENT_LIST_DIR}/zigbee2mqtt/prerm
    ${CMAKE_CURRENT_LIST_DIR}/zigbee2mqtt/postrm)
