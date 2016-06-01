module.exports = (env) ->
  Promise = env.require 'bluebird'
  commons = require('pimatic-plugin-commons')(env)
  M = env.matcher

  exec = Promise.promisify(require("child_process").exec)
  settled = (promise) -> Promise.settle([promise])

  transformError = (error) =>
    if error.code? and error.cause?
      cause = String(error.cause).replace(/(\r\n|\n|\r)/gm," ").trim()
      error = new Error "Command execution failed with exit code #{error.code} (#{cause})"
    return error

  class ShellExecute extends env.plugins.Plugin

    init: (app, @framework, @config) =>

      @framework.ruleManager.addActionProvider(new ShellActionProvider(@framework))

      deviceConfigDef = require("./device-config-schema")

      @framework.deviceManager.registerDeviceClass("ShellSwitch", {
        configDef: deviceConfigDef.ShellSwitch, 
        createCallback: (config, lastState) => return new ShellSwitch(config, lastState)
      })

      @framework.deviceManager.registerDeviceClass("ShellSensor", {
        configDef: deviceConfigDef.ShellSensor, 
        createCallback: (config, lastState) => return new ShellSensor(config, lastState)
      })

      @framework.deviceManager.registerDeviceClass("ShellPresenceSensor", {
        configDef: deviceConfigDef.ShellPresenceSensor,
        createCallback: (config, lastState) => return new ShellPresenceSensor(config, lastState)
      })

      if @config.sequential
        realExec = exec
        lastAction = Promise.resolve()
        exec = (command) ->
          lastAction = settled(lastAction).then( -> realExec(command) )
          return lastAction


  plugin = new ShellExecute()

  class ShellSwitch extends env.devices.PowerSwitch

    constructor: (@config, lastState) ->
      @name = @config.name
      @id = @config.id
      @base = commons.base @, @config.class

      @_state = lastState?.state?.value or off

      updateValue = =>
        if @config.interval > 0
          @getState().finally( =>
            setTimeout(updateValue, @config.interval) 
          )

      super()
      if @config.getStateCommand?
        updateValue()
        
    getState: () ->
      if not @config.getStateCommand?
        return Promise.resolve @_state
      else
        return exec(@config.getStateCommand).then( (streams) =>
          stdout = streams[0]
          stderr = streams[1]
          stdout = stdout.trim()

          switch stdout
            when "on", "true", "1", "t", "o"
              @_setState(on)
              return Promise.resolve @_state
            when "off", "false", "0", "f"
              @_setState(off)
              return Promise.resolve @_state
            else
              @base.error "stderr output from getStateCommand for #{@name}: #{stderr}" if stderr.length isnt 0
              throw new Error "unknown state=\"#{stdout}\"!"
        ).catch( (error) =>
          @base.rejectWithErrorString Promise.reject, transformError(error)
        )
        
    changeStateTo: (state) ->
      if @state is state then return
      # and execute it.
      command = (if state then @config.onCommand else @config.offCommand)
      return exec(command).then( (streams) =>
        stdout = streams[0]
        stderr = streams[1]
        @base.error "stderr output from on/offCommand for #{@name}: #{stderr}" if stderr.length isnt 0
        @_setState(state)
      ).catch( (error) =>
        @base.rejectWithErrorString Promise.reject, transformError(error)
      )
  
  class ShellSensor extends env.devices.Sensor

    constructor: (@config, lastState) ->
      @name = @config.name
      @id = @config.id
      @base = commons.base @, @config.class

      attributeName = @config.attributeName
      @attributeValue = lastState?[attributeName]?.value

      @attributes = {}
      @attributes[attributeName] =
        description: attributeName
        type: @config.attributeType

      if @config.attributeUnit.length > 0
        @attributes[attributeName].unit = @config.attributeUnit

      if @config.attributeAcronym.length > 0
        @attributes[attributeName].acronym = @config.attributeAcronym

      if @config.discrete?
        @attributes[attributeName].discrete = @config.discrete

      # Create a getter for this attribute
      getter = 'get' + attributeName[0].toUpperCase() + attributeName.slice(1)
      @[getter] = () => 
        if @attributeValue? then Promise.resolve(@attributeValue) 
        else @_getUpdatedAttributeValue() 

      updateValue = =>
        if @config.interval > 0
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
          throw new Error("Error getting attribute value for #{@name}: #{stderr}")

        @attributeValue = stdout.trim()
        if @config.attributeType is "number" then @attributeValue = parseFloat(@attributeValue)
        @emit @config.attributeName, @attributeValue
        return @attributeValue
      ).catch( (error) =>
        @base.rejectWithErrorString Promise.reject, transformError(error)
      )

  class ShellPresenceSensor extends env.devices.PresenceSensor

    constructor: (@config, lastState) ->
      @name = @config.name
      @id = @config.id
      @base = commons.base @, @config.class

      @_presence = lastState?.presence?.value or false
      @_triggerAutoReset()

      updateValue = =>
        if @config.interval > 0
          @getPresence().finally( =>
            setTimeout(updateValue, @config.interval)
          )

      super()
      updateValue()

    _triggerAutoReset: ->
      if @config.autoReset and @_presence
        clearTimeout(@_resetPresenceTimeout) if @_resetPresenceTimeout?
        @_resetPresenceTimeout = setTimeout(
          ( => @_setPresence no )
          , @config.resetTime
        )

    getPresence: () ->
      return exec(@config.command).then( (streams) =>
        stdout = streams[0]
        stderr = streams[1]
        stdout = stdout.trim()

        switch stdout
          when "present", "true", "1", "t"
            @_setPresence yes
            @_triggerAutoReset()
            return Promise.resolve yes
          when "absent", "false", "0", "f"
            @_setPresence no
            return Promise.resolve no
          else
            @base.error "stderr output from presence command for #{@name}: #{stderr}" if stderr.length isnt 0
            throw new Error "unknown state=\"#{stdout}\"!"
      ).catch( (error) =>
        @base.rejectWithErrorString Promise.reject, transformError(error)
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
      @base = commons.base @, "ShellActionHandler"

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
            @base.error "stderr output from command #{command}: #{stderr}" if stderr.length isnt 0
            return __("executed \"%s\": %s", command, stdout.trim())
          ).catch( (error) =>
            @base.rejectWithErrorString Promise.reject, transformError(error)
          )
      )

  return plugin