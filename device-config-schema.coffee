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
        description: "
          the command to execute to get current state. 
          Can return on/off, true/false or 1/0 as string
        "
        type: "string"
        required: false
      interval:
        description: "
          the time in ms, the command gets executed to get the actual state. 
          If 0 then the state will not updated automatically.
        "
        type: "integer"
        default: 0
  }
  ShellSensor: {
    title: "ShellSensor config options"
    type: "object"
    extensions: ["xLink"]
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
      discrete:
        description: "
          Should be set to true if the value does not change continuously over time.
        "
        type: "boolean"
        required: false
      command:
        description: "the command to execute and read the attribute value from stdout"
        type: "string"
        default: "echo value"
      interval:
        description: "the time in ms, the command gets executed to get a new sensor value"
        type: "integer"
        default: 5000
  }
  ShellPresenceSensor: {
    title: "ShellPresenceSensor config options"
    type: "object"
    extensions: ["xLink", "xPresentLabel", "xAbsentLabel"]
    properties:
      command:
        description: "
          the command to execute to get the presence state.
          Can return on/off, true/false or 1/0 as string
        "
        type: "string"
        default: "echo false"
      interval:
        description: "
          the time in ms, the command gets executed to get the actual state.
          If 0 then the state will not updated automatically.
        "
        type: "integer"
        default: 0
      autoReset:
        description: "
          if true and the the device is present, reset the state to absent
          after resetTime has been reached.
        "
        type: "boolean"
        default: false
      resetTime:
        description: "Time in milliseconds after that the presence value is reset to absent."
        type: "integer"
        default: 10000
  }
}
