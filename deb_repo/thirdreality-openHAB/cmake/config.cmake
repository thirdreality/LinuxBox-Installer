set(CONFIG_OPENHAB_VERSION
    "4.3.6"
    CACHE STRING "openhab version")
set(CONFIG_OPENHAB_HTTP_PORT
    "8080"
    CACHE STRING "openhab http port")
set(CONFIG_OPENHAB_HTTPS_PORT
    "8443"
    CACHE STRING "openhab https port")
option(CONFIG_INCLUDE_OPENHAB_ADDONS "include openhab addons" OFF)

set(CONFIG_Z2M_FRONTEND_PORT
    "8099"
    CACHE STRING "zigbee2mqtt frontend port")
