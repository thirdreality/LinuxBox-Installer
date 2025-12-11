const {} = require('zigbee-herdsman-converters/lib/modernExtend');
const fz = require('zigbee-herdsman-converters/converters/fromZigbee');
const tz = require('zigbee-herdsman-converters/converters/toZigbee');
const exposes = require('zigbee-herdsman-converters/lib/exposes');
const reporting = require('zigbee-herdsman-converters/lib/reporting');
const ota = require('zigbee-herdsman-converters/lib/ota');
const utils = require('zigbee-herdsman-converters/lib/utils');
const globalStore = require('zigbee-herdsman-converters/lib/store');
const e = exposes.presets;
const ea = exposes.access;
const {deviceAddCustomCluster} = require('zigbee-herdsman-converters/lib/modernExtend');
const m = require('zigbee-herdsman-converters/lib/modernExtend');


module.exports = [{
    zigbeeModel: ["3RSB22BZ"],
    model: "3RSB22BZ",
    vendor: "Third Reality",
    description: "Smart button",
    fromZigbee: [fz.itcmdr_clicks],
    ota: true,
    exposes: [e.action(["single", "double", "hold", "release"])],
    extend: [
        m.battery(),
        m.forcePowerSource({powerSource: "Battery"}),
        m.deviceAddCustomCluster("3rButtonSpecialCluster", {
            ID: 0xff01,
            manufacturerCode: 0x1233,
            attributes: {
                cancelDoubleClick: {ID: 0x0000, type: 0x20},
            },
            commands: {},
            commandsResponse: {},
        }),
        m.text({
            name: "location_describe",
            cluster: "genBasic",
            attribute: "locationDesc",
            description: "Location of equipment",
            access: "STATE_GET",
        }),
    ],
}, ];