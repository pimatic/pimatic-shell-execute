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

Commands are executed parallel by default. With the optional boolean attribute `sequential`set to `true`shell commands are executed sequentially.

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

### ShellButtons Device

Set the `class` attribute to `ShellButtons`. For example:

    { 
      "id": "tv",
      "name": "TV",
      "class": "ShellButtons",
      "buttons": [
        {
          "id": "power",
          "text": "Power",
          "triggerCommand": "irsend SEND_ONCE DEVICENAME KEY_POWER"
        },
        {
          "id": "color",
          "text": "color",
          "triggerCommand": "irsend SEND_ONCE DEVICENAME KEY_INPUT"
        },
        {
          "id": "vol-up",
          "text": "Vol +",
          "triggerCommand": "irsend SEND_ONCE DEVICENAME KEY_VOLUMEUP"
        },
        {
          "id": "vol-down",
          "text": "Vol -",
          "triggerCommand": "irsend SEND_ONCE DEVICENAME KEY_VOLUMEDOWN"
        }
      ]
    }

It also supports `getStateCommand` and `interval` option for every button.

### ShellSensor Device

You can define a sensor device with an attribute which gets updated with the output of shell command:

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

If you're running pimatic on a RaspberryPi, you can use the following sensors for a quick overview of your system health:

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
