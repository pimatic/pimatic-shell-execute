module.exports = {
  title: "shell execute config options"
  type: "object"
  properties:
    debug:
      description: "Debug mode. Writes debug messages to the pimatic log, if set to true."
      type: "boolean"
      default: false
    sequential:
      description: "
        Run all shell commands sequentially (not in parallel). Enable
        this if you have commands that should not be executed in parallel
      "
      type: "boolean"
      default: false
    shell:
      description: "
        Shell to execute a command with. Default:
        '/bin/sh' on UNIX, 'cmd.exe' on Windows
      "
      type: "string"
      required: false
    cwd:
      description: "Current working directory of the child process"
      type: "string"
      required: false
    timeout:
      description: "child process will be killed if it runs longer than timeout milliseconds"
      type: "integer"
      default: 15000
}