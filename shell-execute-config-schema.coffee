module.exports = {
  title: "shell execute config options"
  type: "object"
  properties:
    sequential:
      description: "
        Run all shell commands sequential (not in parallel). Enable
        this if you have commands that should not be execute in parallel
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
}