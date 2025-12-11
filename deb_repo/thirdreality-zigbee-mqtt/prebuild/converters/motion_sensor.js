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

// 修复的UTC时间转换函数，移除T和Z
const fzLocal = {
    fixed_utc_time: {
        cluster: 'genTime',
        type: ['attributeReport', 'readResponse'],
        convert: (model, msg, publish, options, meta) => {
            if (msg.data.time !== undefined) {
                try {
                    const date = new Date(Date.UTC(1999, 12, 1, 0, 0, 0)); 
                    date.setUTCSeconds(msg.data.time); // 基于UTC时间叠加设备返回的秒数
                    
                    // 移除T和Z的格式化选项
                    const formattedTime = date.toISOString()
                        .replace('T', ' ')  // 将T替换为空格
                        .replace('Z', '')  // 移除Z
                        .split('.')[0];    // 可选：移除毫秒部分
                    
                    return {utc_time: formattedTime};
                } catch (error) {
                    console.error(`UTC时间转换错误: ${error}`);
                    return {utc_time: '转换错误'};
                }
            }
        },
    },
};

module.exports = [{
    zigbeeModel: ['3RMS16BZ'],
    model: '3RMS16BZ',
    vendor: 'Third Reality',
    description: 'Wireless motion sensor',
    
    fromZigbee: [
        fz.ias_occupancy_alarm_1, 
        fz.battery, 
        fzLocal.fixed_utc_time
    ],
    toZigbee: [],
    exposes: [
        e.occupancy(),
        e.battery(),
        e.text('utc_time', ea.STATE).withDescription('Formatted UTC time from the device')
    ],
    configure: async (device, coordinatorEndpoint) => {
        const endpoint = device.getEndpoint(1);
        
        // 绑定并配置时间报告
        await endpoint.bind('genTime', coordinatorEndpoint);
        await reporting.bind(endpoint, coordinatorEndpoint, ['genTime']);
        await endpoint.configureReporting('genTime', [{
            attribute: 'time',
            minimumReportInterval: 60,
            maximumReportInterval: 3600,
            reportableChange: 1,
        }]);
        
        // 读取初始时间值
        await endpoint.read('genTime', ['time']);
    },
    extend: [
        m.deviceAddCustomCluster("3rMotionSpecialCluster", {
            ID: 0xff01,
            manufacturerCode: 0x1233,
            attributes: {
                coolDownTime: {ID: 0x0001, type: 0x21},
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