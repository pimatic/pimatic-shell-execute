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

### ShellSwitch Device

Devices can be defined by adding them to the `devices` section in the config file.
Set the `class` attribute to `ShellSwitch`. For example:

    { 
      "id": "light",
      "name": "Lamp",
      "class": "ShellSwitch", 
      "onCommand": "echo on",
      "offCommand": "echo off",
      "getStateCommand": "echo false",
      "interval": "0"
    }

If the `interval` option is greater than 0 then the `getStateCommmand` is executed in this ms interval to
update the state of the switch. 

### ShellSensor Device

You can define a sensor whose attribute gets updated with the output of shell command:

    { 
      "id": "temperature",
      "name": "Room Temperature",
      "class": "ShellSensor", 
      "attributeName": "temperature",
      "attributeType": "number",
      "attributeUnit": "°C",
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

### ShellSensor Device

You can define a presence sensor whose state gets updated with the output of shell command:

    {
      "id": "presence",
      "name": "NGINX Server",
      "class": "ShellPresenceSensor",
      "command": "[[ `pgrep nginx` ]] && echo 1 || echo 0"
    }

For device configuration options see the [device-config-schema](device-config-schema.coffee) file.
