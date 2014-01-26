module.exports = (env) ->
  convict = env.require "convict"
  Q = env.require 'q'
  assert = env.require 'cassert'

  exec = Q.denodeify(require("child_process").exec)

  class ShellExecute extends env.plugins.Plugin

    init: (app, @framework, config) =>
      conf = convict require("./shell-execute-config-shema")
      conf.load config
      conf.validate()
      @config = conf.get ""

      @framework.ruleManager.addActionHandler(new ShellActionHandler())

    createDevice: (config) =>
      if config.class is "ShellSwitch" 
        @framework.registerDevice(new ShellSwitch config)
        return true
      return false

  plugin = new ShellExecute

  class ShellSwitch extends env.devices.PowerSwitch

    constructor: (config) ->
      conf = convict require("./device-config-shema").ShellSwitch
      conf.load config
      conf.validate()
      @config = conf.get ""

      @name = config.name
      @id = config.id

      super()

    getState: () ->
      if @_state? then return Q @_state

      return exec(@config.getStateCommand).then( (streams) =>
        stdout = streams[0]
        stderr = streams[1]
        stdout = stdout.trim()
        switch stdout
          when "on"
            @_state = on
            return Q @_state
          when "off"
            @_state = off
            return Q @_state
          else 
            env.logger.error stderr
            throw new Error "ShellSwitch: unknown state=\"#{stdout}\"!"
        )
        
    changeStateTo: (state) ->
      if @state is state then return
      # and execue it.
      command = (if state then @config.onCommand else @config.offCommand)
      return exec(command).then( (streams) =>
        stdout = streams[0]
        stderr = streams[1]
        env.logger.error stderr if stderr.length isnt 0
        @_setState(state)
      )

  class ShellActionHandler extends env.actions.ActionHandler
    # ### executeAction()
    ###
    This function handles action in the form of `execute "some string"`
    ###
    executeAction: (actionString, simulate) =>
      # If the action string matches the expected format
      matches = actionString.match ///
        ^execute\s+"(.*)"$
      ///
      if matches?
        # extract the command to execute.
        command = matches[1]
        # If we should just simulate
        if simulate
          # just return a promise fulfilled with a description about what we would do.
          return Q __("would execute \"%s\"", command)
        else
          return exec(command).then( (streams) =>
            stdout = streams[0]
            stderr = streams[1]
            env.logger.error stderr if stderr.length isnt 0
            return __("executed \"%s\": %s", command, stdout)
          )
      else return null

  return plugin