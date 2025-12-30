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

const fzLocal = {
    thirdreality_acceleration: {
        cluster: "3rVirationSpecialcluster",
        type: ["attributeReport", "readResponse"],
        convert: (model, msg, publish, options, meta) => {
            const payload = {};
            if (msg.data.xAxis) payload.x_axis = msg.data.xAxis;
            if (msg.data.yAxis) payload.y_axis = msg.data.yAxis;
            if (msg.data.zAxis) payload.z_axis = msg.data.zAxis;
            return payload;
        },
    },
};

module.exports = [{
    zigbeeModel: ["3RVS01031Z"],
    model: "3RVS01031Z",
    vendor: "Third Reality",
    description: "Zigbee vibration sensor",
    fromZigbee: [fz.ias_vibration_alarm_1, fz.battery, fzLocal.thirdreality_acceleration],
    toZigbee: [],
    ota: true,
    exposes: [e.vibration(), e.battery_low(), e.battery(), e.battery_voltage(), e.x_axis(), e.y_axis(), e.z_axis()],
    configure: async (device, coordinatorEndpoint) => {
        const endpoint = device.getEndpoint(1);
        await endpoint.read("genPowerCfg", ["batteryPercentageRemaining"]);
        device.powerSource = "Battery";
        device.save();
    },
    extend: [
        m.deviceAddCustomCluster("3rVirationSpecialcluster", {
            ID: 0xfff1,
            manufacturerCode: 0x1233,
            attributes: {
                coolDownTime: {ID: 0x0004, type: 0x21},
                xAxis: {ID: 0x0001, type: 0x21},
                yAxis: {ID: 0x0002, type: 0x21},
                zAxis: {ID: 0x0003, type: 0x21},
            },
            commands: {},
            commandsResponse: {},
        }),
        m.onOff(),
        m.text({
            name: "location_describe",
            cluster: "genBasic",
            attribute: "locationDesc",
            description: "Location of equipment",
            access: "STATE_GET",
        }),
    ],
}, ];