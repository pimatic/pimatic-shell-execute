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

      @framework.ruleManager.addActionHandler(new ShellActionHandler())

    createDevice: (config) =>
      if config.class is "ShellSwitch" 
        @framework.registerDevice(new ShellSwitch config)
        return true
      if config.class is "ShellSensor"
        @framework.registerDevice(new ShellSensor config)
      return false

  plugin = new ShellExecute

  class ShellSwitch extends env.devices.PowerSwitch

    constructor: (config) ->
      conf = convict _.cloneDeep(require("./device-config-schema").ShellSwitch)
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

  class ShellSensor extends env.devices.Sensor

    constructor: (config) ->
      conf = convict _.cloneDeep(require("./device-config-schema").ShellSensor)
      conf.load config
      conf.validate()
      @config = conf.get ""

      @name = config.name
      @id = config.id

      attributeName = @config.attributeName

      @attributes = {}
      @attributes[attributeName] =
        description: attributeName
        type: if @config.attributeType is "string" then String else Number

      if @config.attributeUnit.length > 0
        @attributes[attributeName].unit = @config.attributeUnit

      # Create a getter for this attribute
      getter = 'get' + attributeName[0].toUpperCase() + attributeName.slice(1)
      @[getter] = () => if @attributeValue? then Q(@attributeValue) else @_getAttributeValue() 

      updateValue = =>
        @_getAttributeValue().then( =>
          setTimeout(updateValue, @config.interval) 
        )

      updateValue()


    _getAttributeValue: () ->
      return exec(@command).then( (streams) =>
        stdout = streams[0]
        stderr = streams[1]
        if stderr.length isnt 0
          throw new Error("Error getting attribute vale for #{name}: #{stderr}")
        
        @attributeValue = stdout
        @emit @config.attributeName, @attributeValue
        return @attributeValue
      )

  class ShellActionHandler extends env.actions.ActionHandler
    # ### executeAction()
    ###
    This function handles action in the form of `execute "some string"`
    ###
    executeAction: (actionString, simulate, context) =>
      retVal = null
      command = null
      fullMatch = no

      setCommand = (m, str) => command = str
      onEnd = => fullMatch = yes
      
      M(actionString, context)
        .match("execute ")
        .matchString(setCommand)
        .onEnd(onEnd)

      if fullMatch
        if simulate
          # just return a promise fulfilled with a description about what we would do.
          retVal = Q __("would execute \"%s\"", command)
        else
          retVal = exec(command).then( (streams) =>
            stdout = streams[0]
            stderr = streams[1]
            env.logger.error stderr if stderr.length isnt 0
            return __("executed \"%s\": %s", command, stdout)
          )
      return retVal

  return plugin