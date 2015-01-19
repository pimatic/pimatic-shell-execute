# #Shell device configuration options
module.exports = {
  title: "pimatic-shell-execute device config schemas"
  ShellSwitch: {
    title: "ShellSwitch config options"
    type: "object"
    extensions: ["xConfirm", "xLink", "xOnLabel", "xOffLabel"]
    properties:
      onCommand:
        description: "the command to execute for switching on"
        type: "string"
      offCommand:
        description: "the command to execute for switching off"
        type: "string"
      getStateCommand:
        description: "the command to execute to get current state"
        type: "string"
        default: "echo off" 
      interval:
        description: "the time in ms, the command gets executed to get the actual state. If 0 then the state will not updated automatically."
        type: "number"
        default: 0
  }
  ShellSensor: {
    title: "ShellSensor config options"
    type: "object"
    extensions: ["xLink", "xPresentLabel", "xAbsentLabel"]
    properties:
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
  }
}
