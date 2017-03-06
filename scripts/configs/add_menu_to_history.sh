#!/bin/bash -i

set -x

#HISTFILE=/home/pi/.bash_history
#set -o history

# Append the memory history list to the history file
history -a

# Silently add the menu command to the history file
history -s /home/pi/rpidatv/scripts/menu.sh menu

history -w

# Next log-in will see menu command in history


