pimatic shell execute plugin
=======================
This plugin let you define devices that execute shell commands. Additionally, it allows you
to execute shell commands in rule actions. So you can define rules of the form:

    if ... then execute "some command"

Configuration
-------------
You can load the plugin by editing your `config.json` to include:

    { 
       "plugin": "shell-execute"
    }

Commands are executed parallel by default. With the optional boolean attribute 
`sequential`set to `true` all shell commands are executed sequentially. This option 
should be used mindfully it can dramatically slow down the execution of command and
yield other side effects like execution timeouts. 

    { 
       "plugin": "shell-execute",
       "sequential": true
    }
    
Optionally, it is also possible to define the *shell* to be used to execute commands. By default, `'/bin/sh'` is 
used on UNIX, and `'cmd.exe'` on Windows. It is also possible to set the current working directory *(cwd)*. 
By default, the current working directory of pimatic is used.

    { 
       "plugin": "shell-execute",
       "shell": "/bin/bash",
       "cwd": "/home/pi/scripts"
    }
    
By default, processes which did not terminate with 15 seconds will be terminated forcefully. The
timeout value given in milliseconds can be set as shown below. Note, long running processes 
may cause blocking situations in pimatic and may lockup system resources. 
If you need to start long running processes, see section on Trouble Shooting below.

    { 
       "plugin": "shell-execute",
       "timeout": 20000
    }


### ShellSwitch Device

Devices can be defined by adding them to the `devices` section in the config file.
Set the `class` attribute to `ShellSwitch`. For example:

    { 
      "id": "light",
      "name": "Lamp",
      "class": "ShellSwitch", 
      "onCommand": "echo on > /home/pi/switchState",
      "offCommand": "echo off > /home/pi/switchState",
      "getStateCommand": "echo /home/pi/switchState",
      "interval": 10000,
      "forceExecution": false
    }

If the `getStateCommand` option is set and the `interval` option is set to a value greater than 0, 
the `getStateCommand` is executed in this ms interval to update the state of the switch. 

### ShellSensor Device

You can define a sensor device with an attribute which gets 
 updated with the output of shell command:

    { 
      "id": "temperature",
      "name": "Room Temperature",
      "class": "ShellSensor", 
      "attributeName": "temperature",
      "attributeType": "number",
      "attributeUnit": "°C",
      "attributeAcronym": "Room",
      "command": "echo 42.0"
    }

If you're running pimatic on a RaspberryPi, you can use the 
 following sensors for a quick overview of your system health:

    {
      "id": "wlan-strength",
      "name": "WLAN Strength",
      "class": "ShellSensor",
      "attributeName": "wlan-strength",
      "attributeType": "number",
      "attributeUnit": "%",
      "command": "iwconfig wlan0 | grep Signal | sed -n -e 's/^.*Signal level.\\([0-9]*\\).*/\\1/gp'",
      "interval": 15000
    },
    {
      "id": "mem-usage",
      "name": "Memory Usage",
      "class": "ShellSensor",
      "attributeName": "mem-usage",
      "attributeType": "number",
      "attributeUnit": "MB",
      "command": "free -m | awk '$5 ~ /[0-9.]+/ { print $3 }'",
      "interval": 60000
    },
    {
      "id": "disk-usage",
      "name": "Disk Usage",
      "class": "ShellSensor",
      "attributeName": "disk-usage",
      "attributeType": "number",
      "attributeUnit": "%",
      "command": "df | awk '/^\\/dev\\/root/ { printf \"%.1f\", ($3/$2)*100 }'",
      "interval": 300000
    },
    {
      "id": "cpu-temp",
      "name": "CPU Temperature",
      "class": "ShellSensor",
      "attributeName": "cpu-temp",
      "attributeType": "number",
      "attributeUnit": "°C",
      "command": "/opt/vc/bin/vcgencmd measure_temp | cut -d \"=\" -f2 | cut -d \"'\" -f1",
      "interval": 60000
    }


### ShellButtons Device

You can define a button device with buttons that trigger individual shell commands, 
 eliminating the need for individual rules:

    { 
      "id": "tv-remote",
      "name": "TV Remote",
      "class": "ShellButtons",
      "buttons": [
        {
          "id": "tv-power",
          "text": "PWR",
          "onPress": "irsend SEND_ONCE tvset KEY_POWER",
          "confirm": true
        }
      ]
    }
    
The given example shows the possibility to create an infrared remote in the pimatic frontend 
 using the lirc plugin. The `onPress` command can be any bash command or file you may 
 want to execute.

### ShellPresenceSensor Device

You can define a presence sensor whose state gets updated with the output of shell command. In some
use cases the shell command may only detect an external device triggered a "present" event, but cannot 
detect its absence. In such cases, when the`ShellPresenceSensor` is "present" it needs to be 
automatically reset to "absent" after some time. For this you can set to `autoReset` property to true:

    {
      "id": "presence",
      "name": "NGINX Server",
      "class": "ShellPresenceSensor",
      "command": "pgrep nginx >/dev/null && echo 1 || echo 0",
      "autoReset": false,
      "resetTime": 10000
    }

For device configuration options see the [device-config-schema](device-config-schema.coffee) file.

Troubleshooting
-------

### Execution of Long Running Commands

Long running commands should be avoided as they may block pimatic or yield errors when the `timeout` value
in the plugin configuration is set to kill pending processes which is the default. 

If you want to execute a long running command though, write a wrapper script which sends the command
 to the background. You can also use a wrapper command which detaches the process from
 the controlling terminal and send it to the background. 
  * Linux: `nohup <command> &` or `nohup bash -c "<command1>; <command2>" &` 
    if you need to execute multiple commands
  * Windows: `start -b <command>` 
  
  
