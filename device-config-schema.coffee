# #Shell device configuration options

# Defines a `node-convict` config-schema and exports it.
module.exports =

  ShellSwitch:
    onCommand:
      doc: "the command to execute for switching on"
      format: String
      default: null
    offCommand:
      doc: "the command to execute for switching off"
      format: String
      default: null
    getStateCommand:
      doc: "the command to execute to get current state"
      format: String
      default: "echo off"

  ShellSensor:
    attributeName:
      doc: "the name of the attribute the sensor is monitoring"
      format: String
      default: ""
    attributeType:
      doc: "the type of the attribute the sensor is monitoring"
      format: ["string", "number"]
      default: "string"
    attributeUnit:
      doc: "this unit of the attribute the sensor is monitoring"
      format: String
      default: ""
    command:
      doc: "the command to execute and read the attribute value from stdout"
      format: String
      default: "echo value"
    interval:
      doc: "the time in ms, the command gets executed to get a new sensor value"
      format: "nat"
      default: 5000
