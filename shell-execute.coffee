module.exports = (env) ->
  convict = env.require "convict"
  Q = env.require 'q'
  assert = env.require 'cassert'
  _ = env.require 'lodash'
  M = env.matcher

  exec = Q.denodeify(require("child_process").exec)

  class ShellExecute extends env.plugins.Plugin

    init: (app, @framework, config) =>
      conf = convict require("./shell-execute-config-schema")
      conf.load config
      conf.validate()
      @config = conf.get ""

      @framework.ruleManager.addActionProvider(new ShellActionProvider(@framework))

      deviceConfigDef = require("./device-config-schema")

      @framework.registerDeviceClass("ShellSwitch", {
        configDef: deviceConfigDef.ShellSwitch, 
        createCallback: (config) => return new ShellSwitch(config)
      })

      @framework.registerDeviceClass("ShellSensor", {
        configDef: deviceConfigDef.ShellSensor, 
        createCallback: (config) => return new ShellSensor(config)
      })

  plugin = new ShellExecute()

  class ShellSwitch extends env.devices.PowerSwitch

    constructor: (@config) ->
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

  class ShellSensor extends env.devices.Sensor

    constructor: (@config) ->
      @name = config.name
      @id = config.id

      attributeName = @config.attributeName

      @attributes = {}
      @attributes[attributeName] =
        description: attributeName
        type: @config.attributeType

      if @config.attributeUnit.length > 0
        @attributes[attributeName].unit = @config.attributeUnit

      # Create a getter for this attribute
      getter = 'get' + attributeName[0].toUpperCase() + attributeName.slice(1)
      @[getter] = () => if @attributeValue? then Q(@attributeValue) else @_getAttributeValue() 

      updateValue = =>
        @_getAttributeValue().finally( =>
          setTimeout(updateValue, @config.interval) 
        )

      super()
      updateValue()

    _getAttributeValue: () ->
      return exec(@config.command).then( (streams) =>
        stdout = streams[0]
        stderr = streams[1]
        if stderr.length isnt 0
          throw new Error("Error getting attribute vale for #{name}: #{stderr}")
        
        @attributeValue = stdout
        if @config.attributeType is "number" then @attributeValue = parseFloat(@attributeValue)
        @emit @config.attributeName, @attributeValue
        return @attributeValue
      )

  class ShellActionProvider extends env.actions.ActionProvider

    constructor: (@framework) -> 
    # ### executeAction()
    ###
    This function handles action in the form of `execute "some string"`
    ###
    parseAction: (input, context) =>
      retVal = null
      commandTokens = null
      fullMatch = no

      setCommand = (m, tokens) => commandTokens = tokens
      onEnd = => fullMatch = yes
      
      m = M(input, context)
        .match("execute ")
        .matchStringWithVars(setCommand)
      
      if m.hadMatch()
        match = m.getFullMatch()
        return {
          token: match
          nextInput: input.substring(match.length)
          actionHandler: new ShellActionHandler(@framework, commandTokens)
        }
      else
        return null

  class ShellActionHandler extends env.actions.ActionHandler

    constructor: (@framework, @commandTokens) ->
    # ### executeAction()
    ###
    This function handles action in the form of `execute "some string"`
    ###
    executeAction: (simulate) =>
      @framework.variableManager.evaluateStringExpression(@commandTokens).then( (command) =>
        if simulate
          # just return a promise fulfilled with a description about what we would do.
          return __("would execute \"%s\"", command)
        else
          return exec(command).then( (streams) =>
            stdout = streams[0]
            stderr = streams[1]
            env.logger.error stderr if stderr.length isnt 0
            return __("executed \"%s\": %s", command, stdout)
          )
      )

  return plugin