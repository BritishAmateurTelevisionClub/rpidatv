#!/usr/bin/env bash

# Return Codes
#
# 128  Commanded exit to Linux prompt
# 129  Exit from any app requesting restart of main rpidatvgui
# 130  Exit from rpidatvgui requesting start of siggen
# 131  Exit from rpidatvgui requesting start of spectrum monitor

GUI_RETURN_CODE=129             # Start rpidatvgui on first call

while [ "$GUI_RETURN_CODE" -gt 127 ] 
  do
    case "$GUI_RETURN_CODE" in
      128)
        exit
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
      *)
        exit
      ;;
    esac
  done
exit 

