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
    zigbeeModel: ["3RTHS0224Z"],
    model: "3RTHS0224Z",
    vendor: "Third Reality",
    description: "Temperature and humidity sensor lite",
    extend: [
        m.temperature(),
        m.humidity(),
        m.battery(),
        m.deviceAddCustomCluster("3rSpecialCluster", {
            ID: 0xff01,
            manufacturerCode: 0x1407,
            attributes: {
                celsiusDegreeCalibration: {ID: 0x0031, type: 0x21},
                humidityCalibration: {ID: 0x0032, type: 0x21},
                fahrenheitDegreeCalibration: {ID: 0x0033, type: 0x21},
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
    ota: true,
}, ];