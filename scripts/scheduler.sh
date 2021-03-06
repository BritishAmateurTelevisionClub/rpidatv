#!/usr/bin/env bash

# set -x

# Return Codes
#
# 128  Exit leaving system running
# 129  Exit from any app requesting restart of main rpidatvgui
# 130  Exit from rpidatvgui requesting start of siggen
# 131  Exit from rpidatvgui requesting start of spectrum monitor
# 132  Run Update Script for production load
# 133  Run Update Script for development load
# 160  Shutdown from GUI
# 192  Reboot from GUI

GUI_RETURN_CODE=129             # Start rpidatvgui on first call

while [ "$GUI_RETURN_CODE" -gt 127 ];  do
  case "$GUI_RETURN_CODE" in
    128)
      # Jump out of the loop
      break
    ;;
    129)
      /home/pi/rpidatv/bin/rpidatvgui
      GUI_RETURN_CODE="$?"
    ;;
    130)
      /home/pi/rpidatv/bin/siggen
      GUI_RETURN_CODE="129"
    ;;
    131)
      cd /home/pi/FreqShow
      sudo python freqshow.py
      cd /home/pi
      GUI_RETURN_CODE=129
    ;;
    132)
      cd /home/pi
      /home/pi/update.sh -p
    ;;
    133)
      cd /home/pi
      /home/pi/update.sh -d
    ;;
    160)
      sleep 1
      sudo swapoff -a
      sudo shutdown now
    ;;
    192)
      sleep 1
      sudo swapoff -a
      sudo reboot now
    ;;
    *)
      # Jump out of the loop
      break
    ;;
  esac
done
exit

