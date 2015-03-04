module.exports = (env) ->
  Promise = env.require 'bluebird'
  assert = env.require 'cassert'
  _ = env.require 'lodash'
  M = env.matcher

  exec = Promise.promisify(require("child_process").exec)
  settled = (promise) -> Promise.settle([promise])

  class ShellExecute extends env.plugins.Plugin

    init: (app, @framework, @config) =>

      @framework.ruleManager.addActionProvider(new ShellActionProvider(@framework))

      deviceConfigDef = require("./device-config-schema")

      @framework.deviceManager.registerDeviceClass("ShellSwitch", {
        configDef: deviceConfigDef.ShellSwitch, 
        createCallback: (config) => return new ShellSwitch(config)
      })

      @framework.deviceManager.registerDeviceClass("ShellSensor", {
        configDef: deviceConfigDef.ShellSensor, 
        createCallback: (config) => return new ShellSensor(config)
      })

      if @config.sequential
        realExec = exec
        lastAction = Promise.resolve()
        exec = (command) ->
          lastAction = settled(lastAction).then( -> realExec(command) )
          return lastAction


  plugin = new ShellExecute()

  class ShellSwitch extends env.devices.PowerSwitch

    constructor: (@config) ->
      @name = config.name
      @id = config.id

      updateValue = =>
        if @config.interval > 0
          @getState().finally( =>
            setTimeout(updateValue, @config.interval) 
          )

      super()
      updateValue()
        
    getState: () ->
      return exec(@config.getStateCommand).then( (streams) =>
        stdout = streams[0]
        stderr = streams[1]
        stdout = stdout.trim()
        
        switch stdout
          when "on", "true", "1", "t", "o"
            @_setState(on)
            @_state = on
            return Promise.resolve @_state
          when "off", "false", "0", "f"
            @_setState(off)
            @_state = off
            return Promise.resolve @_state
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

      if @config.discrete?
        @attributes[attributeName].discrete = @config.discrete

      # Create a getter for this attribute
      getter = 'get' + attributeName[0].toUpperCase() + attributeName.slice(1)
      @[getter] = () => 
        if @attributeValue? then Promise.resolve(@attributeValue) 
        else @_getUpdatedAttributeValue() 

      updateValue = =>
        @_getUpdatedAttributeValue().finally( =>
          setTimeout(updateValue, @config.interval) 
        )

      super()
      updateValue()

    _getUpdatedAttributeValue: () ->
      return exec(@config.command).then( (streams) =>
        stdout = streams[0]
        stderr = streams[1]
        if stderr.length isnt 0
          throw new Error("Error getting attribute vale for #{@name}: #{stderr}")
        
        @attributeValue = stdout.trim()
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
            return __("executed \"%s\": %s", command, stdout.trim())
          )
      )

  return plugin