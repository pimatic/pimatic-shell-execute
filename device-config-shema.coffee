# #Shell device configuration options

# Defines a `node-convict` config-shema and exports it.
module.exports =
  ShellSwitch
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