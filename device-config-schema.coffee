# #Shell device configuration options

# Defines a `node-convict` config-schema and exports it.
module.exports =
  ShellSwitch:
    onCommand:
      description: "the command to execute for switching on"
      type: "string"
      default: null
    offCommand:
      description: "the command to execute for switching off"
      type: "string"
      default: null
    getStateCommand:
      description: "the command to execute to get current state"
      type: "string"
      default: "echo off"
  ShellSensor:
    attributeName:
      description: "the name of the attribute the sensor is monitoring"
      type: "string"
      default: ""
    attributeType:
      description: "the type of the attribute the sensor is monitoring"
      type: "string"
      enum: ["string", "number"]
      default: "string"
    attributeUnit:
      description: "this unit of the attribute the sensor is monitoring"
      type: "string"
      default: ""
    command:
      description: "the command to execute and read the attribute value from stdout"
      type: "string"
      default: "echo value"
    interval:
      description: "the time in ms, the command gets executed to get a new sensor value"
      type: "number"
      default: 5000
