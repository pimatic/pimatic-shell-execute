module.exports = (env) ->
  Promise = env.require 'bluebird'
  commons = require('pimatic-plugin-commons')(env)
  M = env.matcher
  child_process = require("child_process")

  exec = (command, options) ->
    return new Promise( (resolve, reject) ->
      child_process.exec(command, options, (err, stdout, stderr) ->
        if err
          err.stdout = stdout.toString() if stdout?
          err.stderr = stderr.toString() if stderr?
          return reject(err)
        return resolve({stdout: stdout.toString(), stderr: stderr.toString()})
      )
    )
  settled = (promise) -> Promise.settle([promise])

  transformError = (error) ->
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

      @framework.deviceManager.registerDeviceClass("ShellButtons", {
        configDef: deviceConfigDef.ShellButtons,
        createCallback: (config, lastState) ->
          return new ShellButtons(config, lastState)
      })

      @framework.deviceManager.registerDeviceClass("ShellSensor", {
        configDef: deviceConfigDef.ShellSensor, 
        createCallback: (config, lastState) => return new ShellSensor(config, lastState)
      })

      @framework.deviceManager.registerDeviceClass("ShellPresenceSensor", {
        configDef: deviceConfigDef.ShellPresenceSensor,
        createCallback: (config, lastState) => return new ShellPresenceSensor(config, lastState)
      })

      @framework.deviceManager.registerDeviceClass("ShellShutterController", {
        configDef: deviceConfigDef.ShellShutterController, 
        createCallback: (config, lastState) => return new ShellShutterController(config, lastState)
      })

      if @config.sequential
        realExec = exec
        lastAction = Promise.resolve()
        exec = (command, options) ->
          lastAction = settled(lastAction).then( -> realExec(command, options) )
          return lastAction

      @execOptions =
        shell: @config.shell
        cwd: @config.cwd


  plugin = new ShellExecute()

  class ShellSwitch extends env.devices.PowerSwitch

    constructor: (@config, lastState) ->
      @name = @config.name
      @id = @config.id
      @base = commons.base @, @config.class
      @forceExecution = @config.forceExecution

      @_state = lastState?.state?.value or off

      updateValue = =>
        if @config.interval > 0
          @_updateValueTimeout = null
          @getState().finally( =>
            @_updateValueTimeout = setTimeout(updateValue, @config.interval)
          )

      super()
      if @config.getStateCommand?
        updateValue()

    destroy: () ->
      clearTimeout @_updateValueTimeout if @_updateValueTimeout?
      super()

    getState: () ->
      if not @config.getStateCommand?
        return Promise.resolve @_state
      else
        return exec(@config.getStateCommand, plugin.execOptions).then( ({stdout, stderr}) =>
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
      if @_state is state and not @forceExecution then return Promise.resolve()
      # and execute it.
      command = (if state then @config.onCommand else @config.offCommand)
      return exec(command, plugin.execOptions).then( ({stdout, stderr}) =>
        @base.error "stderr output from on/offCommand for #{@name}: #{stderr}" if stderr.length isnt 0
        @_setState(state)
      ).catch( (error) =>
        @base.rejectWithErrorString Promise.reject, transformError(error)
      )

  class ShellButtons extends env.devices.ButtonsDevice

    constructor: (@config, lastState) ->
      @name = @config.name
      @id = @config.id
      @base = commons.base @, @config.class

      # pass config to parent constructor
      super(@config)

    destroy: () ->
      super()

    getButton: -> Promise.resolve(@_lastPressedButton)

    buttonPressed: (buttonId) ->
      for b in @config.buttons
        if b.id is buttonId
          command = b.onPress
          return exec(command, plugin.execOptions).then( ({stdout, stderr}) =>
            @base.error "stderr output from on/offCommand for
              #{@name}: #{stderr}" if stderr.length isnt 0
          ).catch( (error) =>
            @base.rejectWithErrorString Promise.reject, transformError(error)
          )
      throw new Error("No button with the id #{buttonId} found")

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
          @_updateValueTimeout = null
          @_getUpdatedAttributeValue().finally( =>
            @_updateValueTimeout = setTimeout(updateValue, @config.interval)
          )

      super()
      updateValue()

    destroy: () ->
      clearTimeout @_updateValueTimeout if @_updateValueTimeout?
      super()

    _getUpdatedAttributeValue: () ->
      return exec(@config.command, plugin.execOptions).then( ({stdout, stderr}) =>
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
          @_updateValueTimeout = null
          @getPresence().finally( =>
            @_updateValueTimeout = setTimeout(updateValue, @config.interval)
          )

      super()
      updateValue()

    destroy: () ->
      clearTimeout @_updateValueTimeout if @_updateValueTimeout?
      clearTimeout @_resetPresenceTimeout if @_resetPresenceTimeout?
      super()

    _triggerAutoReset: ->
      if @config.autoReset and @_presence
        clearTimeout(@_resetPresenceTimeout) if @_resetPresenceTimeout?
        @_resetPresenceTimeout = setTimeout(
          ( () =>
            @_setPresence no
            @_resetPresenceTimeout = null
          )
          , @config.resetTime
        )

    getPresence: () ->
      return exec(@config.command, plugin.execOptions).then( ({stdout, stderr}) =>
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

  class ShellShutterController extends env.devices.ShutterController

    constructor: (@config, lastState) ->
      @name = @config.name
      @id = @config.id
      @base = commons.base @, @config.class

      @_position= lastState?.position?.value or null

      updateValue = =>
        if @config.interval > 0
          @_updateValueTimeout = null
          @getPosition().finally( =>
            @_updateValueTimeout = setTimeout(updateValue, @config.interval)
          )

      super()
      if @config.getPositionCommand?
        updateValue()

    destroy: () ->
      clearTimeout @_updateValueTimeout if @_updateValueTimeout?
      super()

    getPosition: () ->
      if not @config.getPositionCommand?
        return Promise.resolve @_position
      else
        return exec(@config.getPositionCommand).then( ({stdout, stderr}) =>
          stdout = stdout.trim()

          switch stdout
            when "up", "on", "true", "1", "t", "o"
              @_setPosition("up")
              return Promise.resolve @_position
            when "down", "off", "false", "0", "f"
              @_setPosition("down")
              return Promise.resolve @_position
            when "stopped", "stop"
              @_setPosition("down")
              return Promise.resolve @_position
            else
              @base.error "stderr output from getPositionCommand for #{@name}: #{stderr}" if stderr.length isnt 0
              throw new Error "unknown state=\"#{stdout}\"!"
        ).catch( (error) =>
          @base.rejectWithErrorString Promise.reject, transformError(error)
        )

    moveToPosition: (position) ->
      if @_position is position then return
      # and execute it.
      command = (
        switch position
          when "up" then @config.upCommand
          when "down" then @config.downCommand
          when "stopped" then @config.stopCommand
      )
      return exec(command).then( ({stdout, stderr}) =>
        @base.error "stderr output from up/down/stopCommand for #{@name}: #{stderr}" if stderr.length isnt 0
        @_setPosition(position)
      ).catch( (error) =>
        @base.rejectWithErrorString Promise.reject, transformError(error)
      )

    stop: () -> @moveToPosition("stopped")

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
          return exec(command, plugin.execOptions).then( ({stdout, stderr}) =>
            @base.error "stderr output from command #{command}: #{stderr}" if stderr.length isnt 0
            return __("executed \"%s\": %s", command, stdout.trim())
          ).catch( (error) =>
            @base.rejectWithErrorString Promise.reject, transformError(error)
          )
      )

  return plugin