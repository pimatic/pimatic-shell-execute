module.exports = (env) ->
  Promise = env.require 'bluebird'
  commons = require('pimatic-plugin-commons')(env)
  M = env.matcher
  child_process = require("child_process")
  settled = (promise) -> Promise.settle([promise])
  lastCommand = Promise.resolve()

  transformError = (error) ->
#    for x in Object.keys(error)
#      console.log("--------------p", x, error[x])
#    console.log("--------------message", error.message)
#    console.log("--------------name", error.name)
    e = null
    if 'code' of error and error.code?
        msg = __("Command failed with exit code %s", error.code)
    else if 'killed' of error and 'signal' of error and error.killed?
      msg = __("Command exited due to receipt of signal %s", error.signal)
    else
      msg = __("Command failed")

    if error.message?
      cause = String(error.message).replace(/(\r\n|\n|\r)/gm," ").trim()
      e = new Error "#{msg} (#{cause})"
    else
      e = new Error "msg"

    for p in [ 'killed', 'code', 'signal', 'cmd', 'stdout', 'stderr' ]
      if p of error then e[p] = error[p]
    return e

  class ChildProcessManager

    constructor: (@logger, @options) ->
      @children = []
      if @options.sequential is true
        @exec = @_serializedExec

    reapChildren: () ->
      @_destroyed = true
      @logger.debug "Pending Child Processes: #{@children.length}"
      for child in @children
        child.stdout.destroy()
        child.stderr.destroy()
        child.kill('SIGINT')
        setTimeout () =>
          child.kill('SIGKILL')
        , 1000

      @children = []

    _removeChild: (child) ->
      @children = @children.filter (process) -> process.pid isnt child.pid

    _exec: (command) ->
      @logger.debug "Exec: #{command}"
      return new Promise( (resolve, reject) =>
        child = child_process.exec(command, @options, (err, stdout, stderr) =>
          @_removeChild child
          if err
            err.stdout = stdout.toString().trim() if stdout?
            err.stderr = stderr.toString().trim() if stderr?
            reject transformError(err)
          else
            resolve({
              stdout: stdout.toString().trim(),
              stderr: stderr.toString().trim(),
              child: child
            })
        )
        @children.push child
        @logger.debug "Child processes pending: #{@children.length}"
        child.once 'close', (code, signal) =>
          @logger.debug "Child process #{child.pid} exited with code #{code}" if code?
          @logger.debug "Child process #{child.pid} exited due to receipt of signal #{signal}" if signal?

        return child
      )

    _serializedExec: (command) ->
      lastCommand = settled(lastCommand).then( => @_exec(command) )

    exec: (command) -> @_exec(command)

  class ExecutionHelper
    constructor: (@framework, @shell, @config) ->

    _evaluateCmd: (command) =>
      return new Promise( (resolve, reject) =>
        if @config.evaluateCommandStrings is true
          {variables, functions} = @framework.variableManager.getVariablesAndFunctions()
          match = null
          m = M("\"#{command}\" ", M.createParseContext(variables, functions))
          m.matchStringWithVars((m, tokens) => match = tokens)
          if (match?)
            @framework.variableManager.evaluateStringExpression(match).then(resolve).catch(reject)
          else
            reject(new Error("Invalid Expression: #{m.getRemainingInput()}"))

        else
          resolve(command)
      )

    exec: (command) ->
      @_evaluateCmd(command).then (cmd) => @shell.exec(cmd)


  class ShellExecute extends env.plugins.Plugin

    init: (app, @framework, @config) =>

      @framework.ruleManager.addActionProvider(new ShellActionProvider(@framework))
      @debug = @config.debug || false

      deviceConfigDef = require("./device-config-schema")

      @framework.deviceManager.registerDeviceClass("ShellSwitch", {
        configDef: deviceConfigDef.ShellSwitch, 
        createCallback: (config, lastState) =>
          return new ShellSwitch(config, @framework, lastState)
      })

      @framework.deviceManager.registerDeviceClass("ShellButtons", {
        configDef: deviceConfigDef.ShellButtons,
        createCallback: (config, lastState) =>
          return new ShellButtons(config, @framework, lastState)
      })

      @framework.deviceManager.registerDeviceClass("ShellSensor", {
        configDef: deviceConfigDef.ShellSensor, 
        createCallback: (config, lastState) =>
          return new ShellSensor(config, @framework, lastState)
      })

      @framework.deviceManager.registerDeviceClass("ShellPresenceSensor", {
        configDef: deviceConfigDef.ShellPresenceSensor,
        createCallback: (config, lastState) =>
          return new ShellPresenceSensor(config, @framework, lastState)
      })

      @framework.deviceManager.registerDeviceClass("ShellShutterController", {
        configDef: deviceConfigDef.ShellShutterController, 
        createCallback: (config, lastState) =>
          return new ShellShutterController(config, @framework, lastState)
      })

      @execOptions =
        shell: @config.shell ? true
        cwd: @config.cwd
        timeout: @config.timeout unless @config.timeout is 0
        sequential: @config.sequential
        windowsHide: true
        killSignal: 'SIGKILL'

  plugin = new ShellExecute()

  class ShellSwitch extends env.devices.PowerSwitch

    constructor: (@config, @framework, lastState) ->
      @name = @config.name
      @id = @config.id
      super()
      @forceExecution = @config.forceExecution
      @base = commons.base @, @config.class
      @debug = plugin.debug ? false
      @shell = new ChildProcessManager(@base, plugin.execOptions)
      @helper = new ExecutionHelper(@framework, @shell, @config)
      @_destroyed = false

      @_state = lastState?.state?.value or off

      updateValue = =>
        if @config.interval > 0
          @_updateValueTimeout = null
          @getState().catch( =>
            # ignore rejections at this point
          ).finally( =>
            if not @_destroyed
              @_updateValueTimeout = setTimeout(updateValue, @config.interval)
          )

      if @config.getStateCommand?
        updateValue()

    destroy: () ->
      @_destroyed = true
      clearTimeout @_updateValueTimeout if @_updateValueTimeout?
      @shell.reapChildren()
      super()

    getState: () ->
      if @_destroyed
        return Promise.resolve @_state
      else
        if not @config.getStateCommand?
          return Promise.resolve @_state
        else
          return @helper.exec(@config.getStateCommand).then( ({stdout, stderr}) =>
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
            @base.error error
            Promise.reject error
          )
        
    changeStateTo: (state) ->
      if @_destroyed or (@_state is state and not @forceExecution)
        return Promise.resolve()
      else
        # execute state change.
        command = (if state then @config.onCommand else @config.offCommand)
        return @helper.exec(command).then( ({stdout, stderr}) =>
          @base.error "stderr output from on/offCommand for #{@name}: #{stderr}" if stderr.length isnt 0
          @_setState(state)
        ).catch( (error) =>
          @base.rejectWithErrorString Promise.reject, error
        )

  class ShellButtons extends env.devices.ButtonsDevice

    constructor: (@config, @framework, lastState) ->
      super(@config)
      @base = commons.base @, @config.class
      @debug = plugin.debug || false
      @shell = new ChildProcessManager(@base, plugin.execOptions)
      @helper = new ExecutionHelper(@framework, @shell, @config)
      @_destroyed = false

    destroy: () ->
      @_destroyed = true
      @shell.reapChildren()
      super()

    getButton: -> Promise.resolve(@_lastPressedButton)

    buttonPressed: (buttonId) ->
      for b in @config.buttons
        if b.id is buttonId
          @_lastPressedButton = b.id
          @emit 'button', b.id
          command = b.onPress
          if not @_destroyed
            return @helper.exec(command).then( ({stdout, stderr}) =>
              @base.error "stderr output from on/offCommand for
                #{@name}: #{stderr}" if stderr.length isnt 0
            ).catch( (error) =>
              @base.error error
              Promise.reject error
            )
          else
            return Promise.resolve()
      throw new Error("No button with the id #{buttonId} found")


  class ShellSensor extends env.devices.Sensor

    constructor: (@config, @framework, lastState) ->
      @name = @config.name
      @id = @config.id
      @base = commons.base @, @config.class
      @debug = plugin.debug || false
      @shell = new ChildProcessManager(@base, plugin.execOptions)
      @helper = new ExecutionHelper(@framework, @shell, @config)
      @_destroyed = false

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
          @_getUpdatedAttributeValue().catch( =>
            # ignore rejections at this point
          ).finally( =>
            if not @_destroyed
              @_updateValueTimeout = setTimeout(updateValue, @config.interval)
          )

      super()
      updateValue()

    destroy: () ->
      @_destroyed = true
      clearTimeout @_updateValueTimeout if @_updateValueTimeout?
      @shell.reapChildren()
      super()

    _getUpdatedAttributeValue: () ->
      if not @_destroyed
        return @helper.exec(@config.command).then( ({stdout, stderr}) =>
          if stderr.length isnt 0
            throw new Error("Error getting attribute value for #{@name}: #{stderr}")

          @attributeValue = stdout
          if @config.attributeType is "number" then @attributeValue = parseFloat(@attributeValue)
          @emit @config.attributeName, @attributeValue
          return @attributeValue
        ).catch( (error) =>
          @base.rejectWithErrorString Promise.reject, error
        )
      else
        return Promise.resolve(@attributeValue ? null)


  class ShellPresenceSensor extends env.devices.PresenceSensor

    constructor: (@config, @framework, lastState) ->
      @name = @config.name
      @id = @config.id
      super()
      @base = commons.base @, @config.class
      @debug = plugin.debug || false
      @shell = new ChildProcessManager(@base, plugin.execOptions)
      @helper = new ExecutionHelper(@framework, @shell, @config)
      @_destroyed = false
      @_presence = lastState?.presence?.value or false
      @_triggerAutoReset()

      updateValue = =>
        if @config.interval > 0
          @_updateValueTimeout = null
          @getPresence().catch( =>
            # ignore rejections at this point
          ).finally( =>
            if not @_destroyed
              @_updateValueTimeout = setTimeout(updateValue, @config.interval)
          )

      updateValue()

    destroy: () ->
      @_destroyed = true
      clearTimeout @_updateValueTimeout if @_updateValueTimeout?
      clearTimeout @_resetPresenceTimeout if @_resetPresenceTimeout?
      @shell.reapChildren()
      super()

    _triggerAutoReset: ->
      if @config.autoReset and @_presence and not @_destroyed
        clearTimeout(@_resetPresenceTimeout) if @_resetPresenceTimeout?
        @_resetPresenceTimeout = setTimeout(
          ( () =>
            @_setPresence no
            @_resetPresenceTimeout = null
          )
          , @config.resetTime
        )

    getPresence: () ->
      if not @_destroyed
        return @helper.exec(@config.command).then( ({stdout, stderr}) =>
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
          @base.rejectWithErrorString Promise.reject, error
        )
      else
        Promise.resolve @_presence

  class ShellShutterController extends env.devices.ShutterController

    constructor: (@config, @framework, lastState) ->
      @name = @config.name
      @id = @config.id
      super()
      @base = commons.base @, @config.class
      @debug = plugin.debug || false
      @shell = new ChildProcessManager(@base, plugin.execOptions)
      @helper = new ExecutionHelper(@framework, @shell, @config)
      @_destroyed = false
      @_position = lastState?.position?.value or null

      updateValue = =>
        if @config.interval > 0
          @_updateValueTimeout = null
          @getPosition().catch( =>
            # ignore rejections at this point
          ).finally( =>
            if not @_destroyed
              @_updateValueTimeout = setTimeout(updateValue, @config.interval)
          )

      if @config.getPositionCommand?
        updateValue()

    destroy: () ->
      @_destroyed = true
      clearTimeout @_updateValueTimeout if @_updateValueTimeout?
      @shell.reapChildren()
      super()

    getPosition: () ->
      if @_destroyed or not @config.getPositionCommand?
        return Promise.resolve @_position
      else
        return @helper.exec(@config.getPositionCommand).then( ({stdout, stderr}) =>
          switch stdout
            when "up", "on", "true", "1", "t", "o"
              @_setPosition("up")
              return Promise.resolve @_position
            when "down", "off", "false", "0", "f"
              @_setPosition("down")
              return Promise.resolve @_position
            when "stopped", "stop"
              @_setPosition("stopped")
              return Promise.resolve @_position
            else
              @base.error "stderr output from getPositionCommand for #{@name}: #{stderr}" if stderr.length isnt 0
              throw new Error "unknown state=\"#{stdout}\"!"
        ).catch( (error) =>
          @base.rejectWithErrorString Promise.reject, error
        )

    moveToPosition: (position) ->
      if @_destroyed or @_position is position
        return Promise.resolve()
      else
        # execute command
        command = (
          switch position
            when "up" then @config.upCommand
            when "down" then @config.downCommand
            when "stopped" then @config.stopCommand
        )
        return @helper.exec(command).then( ({stdout, stderr}) =>
          @base.error "stderr output from up/down/stopCommand for #{@name}: #{stderr}" if stderr.length isnt 0
          @_setPosition(position)
        ).catch( (error) =>
          @base.rejectWithErrorString Promise.reject, error
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
      @debug = plugin.debug || false
      @shell = new ChildProcessManager(@base, plugin.execOptions)

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
          return @shell.exec(command).then( ({stdout, stderr}) =>
            @base.error "stderr output from command #{command}: #{stderr}" if stderr.length isnt 0
            return __("executed \"%s\": %s", command, stdout)
          ).catch( (error) =>
            @base.rejectWithErrorString Promise.reject, transformError(error)
          )
      )

  return plugin
