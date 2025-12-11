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
    zigbeeModel: ["3RDS17BZ"],
    model: "3RDS17BZ",
    vendor: "Third Reality",
    description: "Door sensor",
    fromZigbee: [fz.ias_contact_alarm_1, fz.battery],
    toZigbee: [],
    ota: true,
    exposes: [e.contact(), e.battery_low(), e.battery(), e.battery_voltage()],
    configure: async (device, coordinatorEndpoint) => {
        const endpoint = device.getEndpoint(1);
        await endpoint.read("genPowerCfg", ["batteryPercentageRemaining"]);
        device.powerSource = "Battery";
        device.save();
    },
    extend: [
        m.deviceAddCustomCluster("3rDoorSpecialCluster", {
            ID: 0xff01,
            manufacturerCode: 0x1233,
            attributes: {
                delayOpenAttrId: {ID: 0x0000, type: 0x21},
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