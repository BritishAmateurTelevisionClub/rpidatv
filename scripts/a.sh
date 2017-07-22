#! /bin/bash
# set -x #Uncomment for testing

# Version 201707220

############# SET GLOBAL VARIABLES ####################

PATHRPI="/home/pi/rpidatv/bin"
PATHSCRIPT="/home/pi/rpidatv/scripts"
CONFIGFILE=$PATHSCRIPT"/rpidatvconfig.txt"

############# MAKE SURE THAT WE KNOW WHERE WE ARE ##################

cd /home/pi

############ FUNCTION TO READ CONFIG FILE #############################

get_config_var() {
lua - "$1" "$2" <<EOF
local key=assert(arg[1])
local fn=assert(arg[2])
local file=assert(io.open(fn))
for line in file:lines() do
local val = line:match("^#?%s*"..key.."=(.*)$")
if (val ~= nil) then
print(val)
break
end
end
EOF
}

# ########################## SURE TO KILL ALL PROCESS ################
sudo killall -9 ffmpeg >/dev/null 2>/dev/null
sudo killall rpidatv >/dev/null 2>/dev/null
sudo killall hello_encode.bin >/dev/null 2>/dev/null
sudo killall h264yuv >/dev/null 2>/dev/null
sudo killall -9 avc2ts >/dev/null 2>/dev/null
#sudo killall express_server >/dev/null 2>/dev/null
# Leave Express Server running
sudo killall tcanim >/dev/null 2>/dev/null
# Kill netcat that night have been started for Express Srver
sudo killall netcat >/dev/null 2>/dev/null
sudo killall -9 netcat >/dev/null 2>/dev/null

############ FUNCTION TO IDENTIFY AUDIO DEVICES #############################

detect_audio()
{
  # Returns AUDIO_CARD=1 if any audio dongle, or video dongle with
  # audio, detected.  Else AUDIO_CARD=0

  # Then, depending on the values of  $AUDIO_PREF and $MODE_INPUT it sets
  # AUDIO_CARD_NUMBER (typically 0, 1 or 2)
  # AUDIO_CHANNELS (1 for mic, 2 for video stereo capture)
  # AUDIO_SAMPLE (44100 for mic, 48000 for video stereo capture)

  # Set initial conditions for later testing
  MIC=9
  USBTV=9
  printf "Audio selection = $AUDIO_PREF \n"

  # Check on picture input type
  if [ "$MODE_INPUT" == "ANALOGCAM" ] || [ "$MODE_INPUT" == "ANALOGMPEG-2" ]; then
    PIC_INPUT="ANALOG"
  else
    PIC_INPUT="DIGITAL"
  fi
  printf "Video Input is $PIC_INPUT \n"

  # Fist check if any audio card is present
  arecord -l | grep -q 'card'
  if [ $? != 0 ]; then   ## not present
    AUDIO_CARD=0
    printf "Audio card not present\n"
  else                   ## card detected
    printf "Audio card present\n"
    # Check for the presence of a dedicated audio device
    arecord -l | grep -E -q "USB Audio Device|USB AUDIO|Head|Sound Device"
    if [ $? == 0 ]; then   ## Present
      # Look for the dedicated USB Audio Device, select the line and take
      # the 6th character.  Max card number = 8 !!
      MIC="$(arecord -l | grep -E "USB Audio Device|USB AUDIO|Head|Sound Device" | head -c 6 | tail -c 1)"
    fi
    # Check for the presence of a Video dongle with audio
    arecord -l | grep -E -q \
      "usbtv|U0x534d0x21|DVC90|Cx231xxAudio|STK1160|U0xeb1a0x2861|AV TO USB"
    if [ $? == 0 ]; then   ## Present
      # Look for the video dongle, select the line and take
      # the 6th character.  Max card number = 8 !!
      USBTV="$(arecord -l | grep -E \
        "usbtv|U0x534d0x21|DVC90|Cx231xxAudio|STK1160|U0xeb1a0x2861|AV TO USB" \
        | head -c 6 | tail -c 1)"
    fi

    # Now sort out what card parameters are used
    if [ "$MIC" == "9" ] && [ "$USBTV" == "9" ]; then
      # No known card detected so take the safe option and go for beeps
      AUDIO_CARD=0
    else
      # At least one card detected
      case "$AUDIO_PREF" in
      auto)
        if [ "$USBTV" != "9" ] && [ "$PIC_INPUT" == "ANALOG" ]; then
          AUDIO_CARD=1
          AUDIO_CARD_NUMBER=$USBTV
          AUDIO_CHANNELS=2
          AUDIO_SAMPLE=48000
        elif [ "$MIC" != "9" ] && [ "$PIC_INPUT" != "ANALOG" ]; then
          AUDIO_CARD=1
          AUDIO_CARD_NUMBER=$MIC
          AUDIO_CHANNELS=1
          AUDIO_SAMPLE=44100
        else
          AUDIO_CARD=0
          AUDIO_CHANNELS=1
        fi
      ;;
      mic)
        if [ "$MIC" != "9" ]; then
          AUDIO_CARD=1
          AUDIO_CARD_NUMBER=$MIC
          AUDIO_CHANNELS=1
          AUDIO_SAMPLE=44100
        else
          AUDIO_CARD=0
          AUDIO_CHANNELS=1
        fi
      ;;
      video)
        if [ "$USBTV" != "9" ]; then
          AUDIO_CARD=1
          AUDIO_CARD_NUMBER=$USBTV
          AUDIO_CHANNELS=2
          AUDIO_SAMPLE=48000
        else
          AUDIO_CARD=0
          AUDIO_CHANNELS=1
        fi
       ;;
      bleeps)
        AUDIO_CARD=0
        AUDIO_CHANNELS=1
      ;;
      no_audio) # not implemented yet
        AUDIO_CARD=0
        AUDIO_CHANNELS=0
      ;;
      *)
        # Unidentified selection (may be from old entry in rpidatvconfig.txt) Use auto:
        if [ "$USBTV" != "9" ] && [ "$PIC_INPUT" == "ANALOG" ]; then
          AUDIO_CARD=1
          AUDIO_CARD_NUMBER=$USBTV
          AUDIO_CHANNELS=2
          AUDIO_SAMPLE=48000
        elif [ "$MIC" != "9" ] && [ "$PIC_INPUT" != "ANALOG" ]; then
          AUDIO_CARD=1
          AUDIO_CARD_NUMBER=$MIC
          AUDIO_CHANNELS=1
          AUDIO_SAMPLE=44100
        else
          AUDIO_CARD=0
          AUDIO_CHANNELS=1
        fi
       ;;
      esac
    fi
  fi

  printf "AUDIO_CARD = $AUDIO_CARD\n"
  printf "AUDIO_CARD_NUMBER = $AUDIO_CARD_NUMBER \n"
  printf "AUDIO_CHANNELS = $AUDIO_CHANNELS \n"
  printf "AUDIO_SAMPLE = $AUDIO_SAMPLE \n"
}

############ FUNCTION TO IDENTIFY VIDEO DEVICES #############################

detect_video()
{
  # List the video devices, select the 2 lines for any usb device, then
  # select the line with the device details and delete the leading tab
  VID_USB="$(v4l2-ctl --list-devices 2> /dev/null | \
    sed -n '/usb/,/dev/p' | grep 'dev' | tr -d '\t')"

  # List the video devices, select the 2 lines for any mmal device, then
  # select the line with the device details and delete the leading tab
  VID_PICAM="$(v4l2-ctl --list-devices 2> /dev/null | \
    sed -n '/mmal/,/dev/p' | grep 'dev' | tr -d '\t')"

  if [ "$VID_USB" == '' ]; then
    printf "VID_USB was not found, setting to /dev/video0\n"
    VID_USB="/dev/video0"
  fi
  if [ "$VID_PICAM" == '' ]; then
    printf "VID_PICAM was not found, setting to /dev/video0\n"
    VID_PICAM="/dev/video0"
  fi

  printf "The PI-CAM device string is $VID_PICAM\n"
  printf "The USB device string is $VID_USB\n"
}


############ READ FROM rpidatvconfig.txt and Set PARAMETERS #######################

MODE_INPUT=$(get_config_var modeinput $CONFIGFILE)
TSVIDEOFILE=$(get_config_var tsvideofile $CONFIGFILE)
PATERNFILE=$(get_config_var paternfile $CONFIGFILE)
UDPINADDR=$(get_config_var udpinaddr $CONFIGFILE)
UDPOUTADDR=$(get_config_var udpoutaddr $CONFIGFILE)
CALL=$(get_config_var call $CONFIGFILE)
CHANNEL=$CALL
FREQ_OUTPUT=$(get_config_var freqoutput $CONFIGFILE)
BATC_OUTPUT=$(get_config_var batcoutput $CONFIGFILE)
OUTPUT_BATC="-f flv rtmp://fms.batc.tv/live/$BATC_OUTPUT/$BATC_OUTPUT"

STREAM_URL=$(get_config_var streamurl $CONFIGFILE)
STREAM_KEY=$(get_config_var streamkey $CONFIGFILE)
OUTPUT_STREAM="-f flv $STREAM_URL/$STREAM_KEY"

MODE_OUTPUT=$(get_config_var modeoutput $CONFIGFILE)
SYMBOLRATEK=$(get_config_var symbolrate $CONFIGFILE)
GAIN=$(get_config_var rfpower $CONFIGFILE)
PIDVIDEO=$(get_config_var pidvideo $CONFIGFILE)
PIDAUDIO=$(get_config_var pidaudio $CONFIGFILE)
PIDPMT=$(get_config_var pidpmt $CONFIGFILE)
PIDSTART=$(get_config_var pidstart $CONFIGFILE)
SERVICEID=$(get_config_var serviceid $CONFIGFILE)
LOCATOR=$(get_config_var locator $CONFIGFILE)
PIN_I=$(get_config_var gpio_i $CONFIGFILE)
PIN_Q=$(get_config_var gpio_q $CONFIGFILE)

ANALOGCAMNAME=$(get_config_var analogcamname $CONFIGFILE)
ANALOGCAMINPUT=$(get_config_var analogcaminput $CONFIGFILE)
ANALOGCAMSTANDARD=$(get_config_var analogcamstandard $CONFIGFILE)
VNCADDR=$(get_config_var vncaddr $CONFIGFILE)

AUDIO_PREF=$(get_config_var audio $CONFIGFILE)
CAPTIONON=$(get_config_var caption $CONFIGFILE)

OUTPUT_IP=""

let SYMBOLRATE=SYMBOLRATEK*1000
FEC=$(get_config_var fec $CONFIGFILE)
let FECNUM=FEC
let FECDEN=FEC+1

# Look up the capture device names and parameters
detect_audio
detect_video
ANALOGCAMNAME=$VID_USB

#Adjust the PIDs for non-ffmpeg modes
if [ "$MODE_INPUT" != "CAMMPEG-2" ] && [ "$MODE_INPUT" != "ANALOGMPEG-2" ]; then
  let PIDPMT=$PIDVIDEO-1
fi

######################### Pre-processing for each Output Mode ###############

case "$MODE_OUTPUT" in

  IQ)
    FREQUENCY_OUT=0
    OUTPUT=videots
    MODE=IQ
    $PATHSCRIPT"/ctlfilter.sh"
    $PATHSCRIPT"/ctlvco.sh"
    #GAIN=0
  ;;

  QPSKRF)
    FREQUENCY_OUT=$FREQ_OUTPUT
    OUTPUT=videots
    MODE=RF
  ;;

  BATC)
    # Set Output string "-f flv rtmp://fms.batc.tv/live/"$BATC_OUTPUT"/"$BATC_OUTPUT 
    OUTPUT=$OUTPUT_BATC
    # If CAMH264 is selected, temporarily select CAMMPEG-2
    if [ "$MODE_INPUT" == "CAMH264" ]; then
      MODE_INPUT="CAMMPEG-2"
    fi
    # If ANALOGMPEG-2 is selected, temporarily select ANALOGCAM
    if [ "$MODE_INPUT" == "ANALOGMPEG-2" ]; then
      MODE_INPUT="ANALOGCAM"
    fi
  ;;

  STREAMER)
    # Set Output string "-f flv "$STREAM_URL"/"$STREAM_KEY
    OUTPUT=$OUTPUT_STREAM
    # If CAMH264 is selected, temporarily select CAMMPEG-2
    if [ "$MODE_INPUT" == "CAMH264" ]; then
      MODE_INPUT="CAMMPEG-2"
    fi
    # If ANALOGMPEG-2 is selected, temporarily select ANALOGCAM
    if [ "$MODE_INPUT" == "ANALOGMPEG-2" ]; then
      MODE_INPUT="ANALOGCAM"
    fi
  ;;

  DIGITHIN)
    FREQUENCY_OUT=0
    OUTPUT=videots
    DIGITHIN_MODE=1
    MODE=DIGITHIN
    $PATHSCRIPT"/ctlfilter.sh"
    $PATHSCRIPT"/ctlvco.sh"
    #GAIN=0
  ;;

  DTX1)
    MODE=PARALLEL
    FREQUENCY_OUT=2
    OUTPUT=videots
    DIGITHIN_MODE=0
    #GAIN=0
  ;;

  DATVEXPRESS)
    if pgrep -x "express_server" > /dev/null
    then
      # Express already running
      :
    else
      # Stopped, so make sure the control file is not locked and start it
      # From its own folder otherwise it doesnt read the config file
      sudo rm /tmp/expctrl >/dev/null 2>/dev/null
      cd /home/pi/express_server
      sudo nice -n -40 /home/pi/express_server/express_server  >/dev/null 2>/dev/null &
      cd /home/pi
      sleep 5
    fi
    # Set output for ffmpeg (avc2ts uses netcat to pipe output from videots)
    OUTPUT="udp://127.0.0.1:1314?pkt_size=1316&buffer_size=1316"
    FREQUENCY_OUT=0  # Not used in this mode?
    # Calculate output freq in Hz using floating point
    FREQ_OUTPUTHZ=`echo - | awk '{print '$FREQ_OUTPUT' * 1000000}'`
    echo "set freq "$FREQ_OUTPUTHZ >> /tmp/expctrl
    echo "set fec "$FECNUM"/"$FECDEN >> /tmp/expctrl
    echo "set srate "$SYMBOLRATE >> /tmp/expctrl
    # Set the ports
    $PATHSCRIPT"/ctlfilter.sh"

    # Set the output level based on the band
    INT_FREQ_OUTPUT=${FREQ_OUTPUT%.*}
    if (( $INT_FREQ_OUTPUT \< 100 )); then
      GAIN=$(get_config_var explevel0 $CONFIGFILE);
    elif (( $INT_FREQ_OUTPUT \< 250 )); then
      GAIN=$(get_config_var explevel1 $CONFIGFILE);
    elif (( $INT_FREQ_OUTPUT \< 950 )); then
      GAIN=$(get_config_var explevel2 $CONFIGFILE);
    elif (( $INT_FREQ_OUTPUT \< 2000 )); then
      GAIN=$(get_config_var explevel3 $CONFIGFILE);
    elif (( $INT_FREQ_OUTPUT \< 4400 )); then
      GAIN=$(get_config_var explevel4 $CONFIGFILE);
    else
      GAIN="30";
    fi

    # Set Gain
    echo "set level "$GAIN >> /tmp/expctrl

    # Make sure that carrier mode is off
    echo "set car off" >> /tmp/expctrl
  ;;

  IP)
    FREQUENCY_OUT=0
    OUTPUT_IP="-n"$UDPOUTADDR":10000"
    #GAIN=0
  ;;

  COMPVID)
    FREQUENCY_OUT=0
    OUTPUT="/dev/null"
  ;;

esac

OUTPUT_QPSK="videots"
#MODE_DEBUG=quiet
MODE_DEBUG=debug

# ************************ CALCULATE SYMBOL RATES ******************

# BITRATE TS THEORIC
let BITRATE_TS=SYMBOLRATE*2*188*FECNUM/204/FECDEN

# Calculate the Video Bit Rate for Sound/no sound
if [ "$MODE_INPUT" == "CAMMPEG-2" ] || [ "$MODE_INPUT" == "ANALOGMPEG-2" ]; then
  let BITRATE_VIDEO=(BITRATE_TS*75)/100-74000
else
  let BITRATE_VIDEO=(BITRATE_TS*75)/100-10000
fi

let SYMBOLRATE_K=SYMBOLRATE/1000

# Reduce video resolution at low bit rates
if [ "$BITRATE_VIDEO" -lt 150000 ]; then
  VIDEO_WIDTH=160
  VIDEO_HEIGHT=140
else
  if [ "$BITRATE_VIDEO" -lt 300000 ]; then
    VIDEO_WIDTH=352
    VIDEO_HEIGHT=288
  else
    VIDEO_WIDTH=720
    VIDEO_HEIGHT=576
  fi
fi

# Reduce frame rate at low bit rates
if [ "$BITRATE_VIDEO" -lt 300000 ]; then
  VIDEO_FPS=15
else
  VIDEO_FPS=25
fi

# Clean up before starting fifos
sudo rm videoes
sudo rm videots
sudo rm netfifo
mkfifo videoes
mkfifo videots
mkfifo netfifo

echo "************************************"
echo Bitrate TS $BITRATE_TS
echo Bitrate Video $BITRATE_VIDEO
echo Size $VIDEO_WIDTH x $VIDEO_HEIGHT at $VIDEO_FPS fps
echo "************************************"
echo "ModeINPUT="$MODE_INPUT

OUTPUT_FILE="-o videots"

case "$MODE_INPUT" in

  #============================================ H264 PI CAM INPUT MODE =========================================================
  "CAMH264")

    # Check PiCam is present to prevent kernel panic    
    vcgencmd get_camera | grep 'detected=1' >/dev/null 2>/dev/null
    RESULT="$?"
    if [ "$RESULT" -ne 0 ]; then
      exit
    fi

    # Free up Pi Camera for direct OMX Coding by removing driver
    sudo modprobe -r bcm2835_v4l2

    # Set up the means to transport the stream out of the unit
    case "$MODE_OUTPUT" in
      "BATC")
        : # Do nothing
      ;;
      "STREAMER")
        : # Do nothing
      ;;
      "IP")
        OUTPUT_FILE=""
      ;;
      "DATVEXPRESS")
        echo "set ptt tx" >> /tmp/expctrl
        sudo nice -n -30 netcat -u -4 127.0.0.1 1314 < videots & 
      ;;
      "COMPVID")
        OUTPUT_FILE="/dev/null" #Send avc2ts output to /dev/null
      ;;
      *)
        # For IQ, QPSKRF, DIGITHIN and DTX1
        sudo $PATHRPI"/rpidatv" -i videots -s $SYMBOLRATE_K -c $FECNUM"/"$FECDEN -f $FREQUENCY_OUT -p $GAIN -m $MODE -x $PIN_I -y $PIN_Q &
      ;;
    esac

    # Now generate the stream
    if [ "$AUDIO_CARD" == 0 ]; then
      # ******************************* H264 VIDEO, NO AUDIO ************************************
      $PATHRPI"/avc2ts" -b $BITRATE_VIDEO -m $BITRATE_TS -x $VIDEO_WIDTH -y $VIDEO_HEIGHT -f $VIDEO_FPS -i 100 -p $PIDPMT -s $CHANNEL $OUTPUT_FILE $OUTPUT_IP > /dev/null &
    else
      # ******************************* H264 VIDEO WITH AUDIO (TODO) ************************************
      $PATHRPI"/avc2ts" -b $BITRATE_VIDEO -m $BITRATE_TS -x $VIDEO_WIDTH -y $VIDEO_HEIGHT -f $VIDEO_FPS -i 100 -p $PIDPMT -s $CHANNEL $OUTPUT_FILE $OUTPUT_IP  > /dev/null &
    fi
  ;;

  #============================================ MPEG-2 PI CAM INPUT MODE =============================================================
  "CAMMPEG-2")

# Set up the command for the MPEG-2 Callsign caption

# Note that spaces are not allowed in the CAPTION string below!
if [ "$CAPTIONON" == "on" ]; then
  CAPTION="drawtext=fontfile=/usr/share/fonts/truetype/ttf-dejavu/DejaVuSans.ttf:\
text=$CALL:fontcolor=white:fontsize=36:box=1:boxcolor=black@0.5:boxborderw=5:\
x=(w+w/2+w/8-text_w)/2:y=(h/4-text_h)/2"
  VF="-vf "
else
  CAPTION=""
  VF=""    
fi

    # Size the viewfinder and load the Camera driver
    let OVERLAY_VIDEO_WIDTH=$VIDEO_WIDTH-64
    let OVERLAY_VIDEO_HEIGHT=$VIDEO_HEIGHT-64
    v4l2-ctl --get-fmt-overlay
    v4l2-ctl --set-fmt-video=width=$VIDEO_WIDTH,height=$VIDEO_HEIGHT,pixelformat=0
    v4l2-ctl --set-fmt-overlay=left=0,top=0,width=$OVERLAY_VIDEO_WIDTH,height=$OVERLAY_VIDEO_HEIGHT
    v4l2-ctl -p $VIDEO_FPS

    # If sound arrives first, decrease the numeric number to delay it
    # "-00:00:0.?" works well at SR1000 on IQ mode
    # "-00:00:0.2" works well at SR2000 on IQ mode
    ITS_OFFSET="-00:00:0.2"

    # Set up the means to transport the stream out of the unit
    case "$MODE_OUTPUT" in
      "BATC")
        ITS_OFFSET="-00:00:00"
      ;;
      "STREAMER")
        ITS_OFFSET="-00:00:00"
      ;;
      "IP")
        : # Do nothing
      ;;
      "DATVEXPRESS")
        echo "set ptt tx" >> /tmp/expctrl
        # ffmpeg sends the stream directly to DATVEXPRESS
      ;;
      "COMPVID")
        : # Do nothing
      ;;
      *)
        # For IQ, QPSKRF, DIGITHIN and DTX1 rpidatv generates the IQ (and RF for QPSKRF)
        sudo $PATHRPI"/rpidatv" -i videots -s $SYMBOLRATE_K -c $FECNUM"/"$FECDEN -f $FREQUENCY_OUT -p $GAIN -m $MODE -x $PIN_I -y $PIN_Q &
      ;;
    esac

    # Now generate the stream
    case "$MODE_OUTPUT" in
      "BATC")
        $PATHRPI"/ffmpeg" -loglevel $MODE_DEBUG -itsoffset "$ITS_OFFSET" \
          -f v4l2 -input_format h264 \
          -i /dev/video0 -thread_queue_size 2048 \
          -f alsa -ac $AUDIO_CHANNELS -ar $AUDIO_SAMPLE \
          -i hw:$AUDIO_CARD_NUMBER,0 \
          -framerate 25 -video_size 720x576 -c:v h264_omx -b:v 512k \
          -ar 11025 -ac $AUDIO_CHANNELS -ab 64k \
          -g 25 \
          -f flv rtmp://fms.batc.tv/live/$BATC_OUTPUT/$BATC_OUTPUT &
      ;;
      "STREAMER")
        $PATHRPI"/ffmpeg" -loglevel $MODE_DEBUG -itsoffset "$ITS_OFFSET" \
          -f v4l2 -input_format h264 \
          -i /dev/video0 -thread_queue_size 2048 \
          -f alsa -ac $AUDIO_CHANNELS -ar $AUDIO_SAMPLE \
          -i hw:$AUDIO_CARD_NUMBER,0 \
          -framerate 25 -video_size 720x576 -c:v h264_omx -b:v 512k \
          -ar 11025 -ac $AUDIO_CHANNELS -ab 64k \
          -g 25 \
          -f flv $STREAM_URL/$STREAM_KEY &
      ;;
      *)

        if [ "$AUDIO_CARD" == 0 ]; then
          # ******************************* MPEG-2 VIDEO WITH BEEP ************************************
      
          sudo nice -n -30 $PATHRPI"/ffmpeg" -loglevel $MODE_DEBUG \
            -analyzeduration 0 -probesize 2048  -fpsprobesize 0 -thread_queue_size 512\
            -f v4l2 -framerate $VIDEO_FPS -video_size "$VIDEO_WIDTH"x"$VIDEO_HEIGHT"\
            -i /dev/video0 -fflags nobuffer \
            \
            -f lavfi -ac 1 \
            -i "sine=frequency=500:beep_factor=4:sample_rate=44100:duration=0" \
            \
            -b:v $BITRATE_VIDEO -minrate:v $BITRATE_VIDEO -maxrate:v  $BITRATE_VIDEO\
            -f mpegts  -blocksize 1880 -acodec mp2 -b:a 64K -ar 44100 -ac $AUDIO_CHANNELS\
            -mpegts_original_network_id 1 -mpegts_transport_stream_id 1 \
            -mpegts_service_id $SERVICEID \
            -mpegts_pmt_start_pid $PIDPMT -streamid 0:"$PIDVIDEO" -streamid 1:"$PIDAUDIO" \
            -metadata service_provider=$CALL -metadata service_name=$CHANNEL \
            -muxrate $BITRATE_TS -y $OUTPUT &

        else
          # ******************************* MPEG-2 VIDEO WITH AUDIO ************************************

          # PCR PID ($PIDSTART) seems to be fixed as the same as the video PID.  
          # PMT, Vid and Audio PIDs can all be set. 

          sudo nice -n -30 $PATHRPI"/ffmpeg" -loglevel $MODE_DEBUG -itsoffset "$ITS_OFFSET"\
            -analyzeduration 0 -probesize 2048  -fpsprobesize 0 -thread_queue_size 512\
            -f v4l2 -framerate $VIDEO_FPS -video_size "$VIDEO_WIDTH"x"$VIDEO_HEIGHT"\
            -i /dev/video0 -fflags nobuffer \
            \
            -f alsa -ac $AUDIO_CHANNELS -ar $AUDIO_SAMPLE \
            -i hw:$AUDIO_CARD_NUMBER,0 \
            \
            $VF $CAPTION -b:v $BITRATE_VIDEO -minrate:v $BITRATE_VIDEO -maxrate:v  $BITRATE_VIDEO \
            -f mpegts  -blocksize 1880 -acodec mp2 -b:a 64K -ar 44100 -ac $AUDIO_CHANNELS\
            -mpegts_original_network_id 1 -mpegts_transport_stream_id 1 \
            -mpegts_service_id $SERVICEID \
            -mpegts_pmt_start_pid $PIDPMT -streamid 0:"$PIDVIDEO" -streamid 1:"$PIDAUDIO" \
            -metadata service_provider=$CALL -metadata service_name=$CHANNEL \
            -muxrate $BITRATE_TS -y $OUTPUT &
        fi
      ;;
    esac
  ;;

#============================================ H264 PATERN =============================================================


  "PATERNAUDIO")

    # If PiCam is present unload driver   
    vcgencmd get_camera | grep 'detected=1' >/dev/null 2>/dev/null
    RESULT="$?"
    if [ "$RESULT" -eq 0 ]; then
      sudo modprobe -r bcm2835_v4l2
    fi    

    # Set up means to transport of stream out of unit
    case "$MODE_OUTPUT" in
      "BATC")
        sudo nice -n -30 $PATHRPI"/ffmpeg" -loglevel $MODE_DEBUG -i videots -y $OUTPUT_BATC &
      ;;
      "IP")
        OUTPUT_FILE=""
      ;;
      "DATVEXPRESS")
        echo "set ptt tx" >> /tmp/expctrl
        sudo nice -n -30 netcat -u -4 127.0.0.1 1314 < videots &
      ;;
      "COMPVID")
        OUTPUT_FILE="/dev/null" #Send avc2ts output to /dev/null
      ;;
      *)
        sudo  $PATHRPI"/rpidatv" -i videots -s $SYMBOLRATE_K -c $FECNUM"/"$FECDEN -f $FREQUENCY_OUT -p $GAIN -m $MODE -x $PIN_I -y $PIN_Q &
      ;;
	esac

    # Now generate the stream

    $PATHRPI"/avc2ts" -b $BITRATE_VIDEO -m $BITRATE_TS -x $VIDEO_WIDTH -y $VIDEO_HEIGHT -f $VIDEO_FPS -i 100 $OUTPUT_FILE -t 3 -p $PIDPMT -s $CHANNEL $OUTPUT_IP  &

    $PATHRPI"/tcanim" $PATERNFILE"/*10" "48" "72" "CQ" "CQ CQ CQ DE "$CALL" IN $LOCATOR - DATV $SYMBOLRATEK KS FEC "$FECNUM"/"$FECDEN &

  ;;

#============================================ VNC =============================================================

  "VNC")
    # If PiCam is present unload driver   
    vcgencmd get_camera | grep 'detected=1' >/dev/null 2>/dev/null
    RESULT="$?"
    if [ "$RESULT" -eq 0 ]; then
      sudo modprobe -r bcm2835_v4l2
    fi    

    # Set up means to transport of stream out of unit
    case "$MODE_OUTPUT" in
      "BATC")
        sudo nice -n -30 $PATHRPI"/ffmpeg" -loglevel $MODE_DEBUG -i videots -y $OUTPUT_BATC & 
      ;;
      "IP")
        OUTPUT_FILE=""
      ;;
      "DATVEXPRESS")
        echo "set ptt tx" >> /tmp/expctrl
        sudo nice -n -30 netcat -u -4 127.0.0.1 1314 < videots &
      ;;
      "COMPVID")
        OUTPUT_FILE="/dev/null" #Send avc2ts output to /dev/null
      ;;
      *)
        sudo $PATHRPI"/rpidatv" -i videots -s $SYMBOLRATE_K -c $FECNUM"/"$FECDEN -f $FREQUENCY_OUT -p $GAIN -m $MODE -x $PIN_I -y $PIN_Q &;;
      esac

    # Now generate the stream
    $PATHRPI"/avc2ts" -b $BITRATE_VIDEO -m $BITRATE_TS -x $VIDEO_WIDTH -y $VIDEO_HEIGHT -f $VIDEO_FPS -i 100 $OUTPUT_FILE -t 4 -e $VNCADDR -p $PIDPMT -s $CHANNEL $OUTPUT_IP &

  ;;

  #============================================ ANALOG H264 =============================================================
  "ANALOGCAM")

    # Turn off the viewfinder (which would show Pi Cam)
    v4l2-ctl --overlay=0

    # Set the EasyCap input and video standard
    if [ "$ANALOGCAMINPUT" != "-" ]; then
      v4l2-ctl -d $ANALOGCAMNAME "--set-input="$ANALOGCAMINPUT
    fi
    if [ "$ANALOGCAMSTANDARD" != "-" ]; then
      v4l2-ctl -d $ANALOGCAMNAME "--set-standard="$ANALOGCAMSTANDARD
    fi

    # If PiCam is present unload driver   
    vcgencmd get_camera | grep 'detected=1' >/dev/null 2>/dev/null
    RESULT="$?"
    if [ "$RESULT" -eq 0 ]; then
      sudo modprobe -r bcm2835_v4l2
    fi    

    # Set up means to transport of stream out of unit
    case "$MODE_OUTPUT" in
      "BATC")
        : # Do nothing.  All done below
      ;;
      "STREAMER")
        : # Do nothing.  All done below
      ;;
      "IP")
        OUTPUT_FILE=""
      ;;
      "DATVEXPRESS")
        echo "set ptt tx" >> /tmp/expctrl
        sudo nice -n -30 netcat -u -4 127.0.0.1 1314 < videots &
      ;;
      "COMPVID")
        : # Do nothing.  Mode does not work yet
      ;;
      *)
        sudo $PATHRPI"/rpidatv" -i videots -s $SYMBOLRATE_K -c $FECNUM"/"$FECDEN -f $FREQUENCY_OUT -p $GAIN -m $MODE -x $PIN_I -y $PIN_Q &
      ;;
    esac

    # Now generate the stream
    case "$MODE_OUTPUT" in
      "BATC")
        $PATHRPI"/ffmpeg" -f v4l2 -i $VID_USB -thread_queue_size 1024 \
          -f alsa -ac $AUDIO_CHANNELS -ar $AUDIO_SAMPLE \
          -i hw:$AUDIO_CARD_NUMBER,0 \
          -framerate 25 -video_size 720x576 -c:v h264_omx -b:v 512k \
          -ar 11025 -ac $AUDIO_CHANNELS -ab 64k \
          -vf "format=yuyv422,yadif=0:1:0" -g 25 \
          -f flv rtmp://fms.batc.tv/live/$BATC_OUTPUT/$BATC_OUTPUT &
      ;;
      "STREAMER")
        $PATHRPI"/ffmpeg" -f v4l2 -i $VID_USB -thread_queue_size 2048 \
          -f alsa -ac $AUDIO_CHANNELS -ar $AUDIO_SAMPLE \
          -i hw:$AUDIO_CARD_NUMBER,0 \
          -framerate 25 -video_size 720x576 -c:v h264_omx -b:v 512k \
          -ar 11025 -ac $AUDIO_CHANNELS -ab 64k \
          -vf yadif=0:1:0 -g 25 \
          -f flv $STREAM_URL/$STREAM_KEY &
      ;;
     "COMPVID")
        : # Do nothing.  Mode does not work yet
      ;;
      *)
        $PATHRPI"/avc2ts" -b $BITRATE_VIDEO -m $BITRATE_TS -x $VIDEO_WIDTH -y $VIDEO_HEIGHT\
          -f $VIDEO_FPS -i 100 $OUTPUT_FILE -t 2 -e $ANALOGCAMNAME -p $PIDPMT -s $CHANNEL $OUTPUT_IP &
      ;;
    esac
  ;;

#============================================ DESKTOP H264 =============================================================

  "DESKTOP")
    # If PiCam is present unload driver   
    vcgencmd get_camera | grep 'detected=1' >/dev/null 2>/dev/null
    RESULT="$?"
    if [ "$RESULT" -eq 0 ]; then
      sudo modprobe -r bcm2835_v4l2
    fi    

    # Set up means to transport of stream out of unit
    case "$MODE_OUTPUT" in
      "BATC")
        sudo nice -n -30 $PATHRPI"/ffmpeg" -loglevel $MODE_DEBUG -i videots -y $OUTPUT_BATC &
      ;;
      "IP")
        OUTPUT_FILE=""
      ;;
      "DATVEXPRESS")
        echo "set ptt tx" >> /tmp/expctrl
        sudo nice -n -30 netcat -u -4 127.0.0.1 1314 < videots &
      ;;
      "COMPVID")
        OUTPUT_FILE="/dev/null" #Send avc2ts output to /dev/null
      ;;
      *)
        sudo nice -n -30 $PATHRPI"/rpidatv" -i videots -s $SYMBOLRATE_K -c $FECNUM"/"$FECDEN -f $FREQUENCY_OUT -p $GAIN -m $MODE -x $PIN_I -y $PIN_Q &
      ;;

    esac

    # Now generate the stream
    $PATHRPI"/avc2ts" -b $BITRATE_VIDEO -m $BITRATE_TS -x $VIDEO_WIDTH -y $VIDEO_HEIGHT -f $VIDEO_FPS -i 100 $OUTPUT_FILE -t 3 -p $PIDPMT -s $CHANNEL $OUTPUT_IP &

  ;;

# *********************************** TRANSPORT STREAM INPUT THROUGH IP ******************************************

  "IPTSIN")

    # Set up means to transport of stream out of unit
    case "$MODE_OUTPUT" in
      "BATC")
        sudo nice -n -30 $PATHRPI"/ffmpeg" -loglevel $MODE_DEBUG -i videots -y $OUTPUT_BATC &
      ;;
      "DATVEXPRESS")
        nice -n -30 nc -u -4 127.0.0.1 1314 < videots &
      ;;
      "COMPVID")
        : # Do nothing.  Mode does not work yet
      ;;
      *)
        sudo $PATHRPI"/rpidatv" -i videots -s $SYMBOLRATE_K -c $FECNUM"/"$FECDEN -f $FREQUENCY_OUT -p $GAIN -m $MODE -x $PIN_I -y $PIN_Q &
      ;;
    esac

    # Now generate the stream

    PORT=10000
    # $PATHRPI"/mnc" -l -i eth0 -p $PORT $UDPINADDR > videots &
    # Unclear why Evariste uses multicast address here - my BT router dislikes routing multicast intensely so
    # I have changed it to just listen on the predefined port number for a UDP stream
    netcat -u -4 -l $PORT > videots &
  ;;

  # *********************************** TRANSPORT STREAM INPUT FILE ******************************************

  "FILETS")
    # Set up means to transport of stream out of unit
    case "$MODE_OUTPUT" in
      "BATC")
        sudo nice -n -30 $PATHRPI"/ffmpeg" -loglevel $MODE_DEBUG -i $TSVIDEOFILE -y $OUTPUT_BATC &
      ;;
      "DATVEXPRESS")
        echo "set ptt tx" >> /tmp/expctrl
        sudo nice -n -30 netcat -u -4 127.0.0.1 1314 < $TSVIDEOFILE &
        #sudo nice -n -30 cat $TSVIDEOFILE | sudo nice -n -30 netcat -u -4 127.0.0.1 1314 & 
      ;;
      *)
        sudo $PATHRPI"/rpidatv" -i $TSVIDEOFILE -s $SYMBOLRATE_K -c $FECNUM"/"$FECDEN -f $FREQUENCY_OUT -p $GAIN -m $MODE -l -x $PIN_I -y $PIN_Q &;;
    esac
  ;;

  # *********************************** CARRIER  ******************************************

  "CARRIER")
    case "$MODE_OUTPUT" in
      "DATVEXPRESS")
        echo "set car on" >> /tmp/expctrl
        echo "set ptt tx" >> /tmp/expctrl
      ;;
      *)
        # sudo $PATHRPI"/rpidatv" -i videots -s $SYMBOLRATE_K -c "carrier" -f $FREQUENCY_OUT -p $GAIN -m $MODE -x $PIN_I -y $PIN_Q &

        # Temporary fix for swapped carrier and test modes:
        sudo $PATHRPI"/rpidatv" -i videots -s $SYMBOLRATE_K -c "tesmode" -f $FREQUENCY_OUT -p $GAIN -m $MODE -x $PIN_I -y $PIN_Q &
      ;;
    esac
  ;;

  # *********************************** TESTMODE  ******************************************
  "TESTMODE")
    # sudo $PATHRPI"/rpidatv" -i videots -s $SYMBOLRATE_K -c "tesmode" -f $FREQUENCY_OUT -p $GAIN -m $MODE -x $PIN_I -y $PIN_Q &

    # Temporary fix for swapped carrier and test modes:
    sudo $PATHRPI"/rpidatv" -i videots -s $SYMBOLRATE_K -c "carrier" -f $FREQUENCY_OUT -p $GAIN -m $MODE -x $PIN_I -y $PIN_Q &
  ;;

#============================================ CONTEST H264 =============================================================
  "CONTEST")
    # Select the right image
    INT_FREQ_OUTPUT=${FREQ_OUTPUT%.*}
    if (( $INT_FREQ_OUTPUT \< 100 )); then
      cp -f /home/pi/rpidatv/scripts/images/contest0.png /home/pi/rpidatv/scripts/images/contest.png
    elif (( $INT_FREQ_OUTPUT \< 250 )); then
      cp -f /home/pi/rpidatv/scripts/images/contest1.png /home/pi/rpidatv/scripts/images/contest.png
    elif (( $INT_FREQ_OUTPUT \< 950 )); then
      cp -f /home/pi/rpidatv/scripts/images/contest2.png /home/pi/rpidatv/scripts/images/contest.png
    else
      cp -f /home/pi/rpidatv/scripts/images/contest3.png /home/pi/rpidatv/scripts/images/contest.png
    fi

    # Display the numbers on the desktop
    #sudo killall -9 fbcp >/dev/null 2>/dev/null
    #fbcp & >/dev/null 2>/dev/null  ## fbcp gets started here and stays running. Not called by a.sh
    sudo fbi -T 1 -noverbose -a $PATHSCRIPT"/images/contest.png" >/dev/null 2>/dev/null
    (sleep 1; sudo killall -9 fbi >/dev/null 2>/dev/null) &  ## kill fbi once it has done its work

    # If PiCam is present unload driver   
    vcgencmd get_camera | grep 'detected=1' >/dev/null 2>/dev/null
    RESULT="$?"
    if [ "$RESULT" -eq 0 ]; then
      sudo modprobe -r bcm2835_v4l2
    fi    

    # Set up means to transport of stream out of unit
    case "$MODE_OUTPUT" in
      "BATC")
        sudo nice -n -30 $PATHRPI"/ffmpeg" -loglevel $MODE_DEBUG -i videots -y $OUTPUT_BATC &
      ;;
      "IP")
        OUTPUT_FILE=""
      ;;
      "DATVEXPRESS")
        echo "set ptt tx" >> /tmp/expctrl
        sudo nice -n -30 netcat -u -4 127.0.0.1 1314 < videots &
      ;;
      "COMPVID")
        OUTPUT_FILE="/dev/null" #Send avc2ts output to /dev/null
      ;;
      *)
        sudo nice -n -30 $PATHRPI"/rpidatv" -i videots -s $SYMBOLRATE_K \
          -c $FECNUM"/"$FECDEN -f $FREQUENCY_OUT -p $GAIN -m $MODE -x $PIN_I -y $PIN_Q &

      ;;
    esac

    $PATHRPI"/avc2ts" -b $BITRATE_VIDEO -m $BITRATE_TS -x $VIDEO_WIDTH -y $VIDEO_HEIGHT \
      -f $VIDEO_FPS -i 100 $OUTPUT_FILE -t 3 -p $PIDPMT -s $CHANNEL $OUTPUT_IP &

  ;;
  #============================================ ANALOG MPEG-2 INPUT MODE =============================================================
  "ANALOGMPEG-2")

    # Turn off the viewfinder (which would show Pi Cam)
    v4l2-ctl --overlay=0

    # Set up the command for the MPEG-2 Callsign caption
     if [ "$CAPTIONON" == "on" ]; then
      CAPTION="drawtext=fontfile=/usr/share/fonts/truetype/ttf-dejavu/DejaVuSans.ttf: \
        text=\'$CALL\': fontcolor=white: fontsize=36: box=1: boxcolor=black@0.5: \
        boxborderw=5: x=(w+w/2+w/8-text_w)/2: y=(h/4-text_h)/2, "
    else
      CAPTION=""    
    fi

    # Set the EasyCap input and PAL/NTSC standard
    if [ "$ANALOGCAMINPUT" != "-" ]; then
      v4l2-ctl -d $ANALOGCAMNAME "--set-input="$ANALOGCAMINPUT
    fi
    if [ "$ANALOGCAMSTANDARD" != "-" ]; then
      v4l2-ctl -d $ANALOGCAMNAME "--set-standard="$ANALOGCAMSTANDARD
    fi

    # Set the sound/video lipsync
    # If sound arrives first, decrease the numeric number to delay it
    # "-00:00:0.?" works well at SR1000 on IQ mode
    # "-00:00:0.2" works well at SR2000 on IQ mode
    ITS_OFFSET="-00:00:0.2"

    # Set up the means to transport the stream out of the unit
    case "$MODE_OUTPUT" in
      "BATC")
        ITS_OFFSET="-00:00:5.0"
        #sudo nice -n -30 $PATHRPI"/ffmpeg" -i videots -y $OUTPUT_STREAM &
        sudo nice -n -30 $PATHRPI"/ffmpeg" -i videots -y  -video_size 640x480\
          -b:v 500k -maxrate 700k -bufsize 2048k $OUTPUT_BATC &
        OUTPUT="videots"
      ;;
      "STREAMER")
        ITS_OFFSET="-00:00:5.0"
        #sudo nice -n -30 $PATHRPI"/ffmpeg" -i videots -y $OUTPUT_STREAM &
        sudo nice -n -30 $PATHRPI"/ffmpeg" -i videots -y  -video_size 640x480\
          -b:v 500k -maxrate 700k -bufsize 2048k $OUTPUT_STREAM &
        OUTPUT="videots"
      ;;
      "IP")
        : # Do nothing
      ;;
      "DATVEXPRESS")
        echo "set ptt tx" >> /tmp/expctrl
        # ffmpeg sends the stream directly to DATVEXPRESS
      ;;
      "COMPVID")
        : # Do nothing
      ;;
      *)
        # For IQ, QPSKRF, DIGITHIN and DTX1 rpidatv generates the IQ (and RF for QPSKRF)
        sudo $PATHRPI"/rpidatv" -i videots -s $SYMBOLRATE_K -c $FECNUM"/"$FECDEN -f $FREQUENCY_OUT -p $GAIN -m $MODE -x $PIN_I -y $PIN_Q &
      ;;
    esac

    # Now generate the stream
    if [ "$AUDIO_CARD" == 0 ]; then
      # ******************************* MPEG-2 ANALOG VIDEO WITH BEEP ************************************
      
      sudo nice -n -30 $PATHRPI"/ffmpeg" -loglevel $MODE_DEBUG -itsoffset "$ITS_OFFSET"\
        -analyzeduration 0 -probesize 2048  -fpsprobesize 0 -thread_queue_size 512\
        -f v4l2 -framerate $VIDEO_FPS -video_size "$VIDEO_WIDTH"x"$VIDEO_HEIGHT"\
        -i $VID_USB -fflags nobuffer \
        \
        -f lavfi -ac 1 \
        -i "sine=frequency=500:beep_factor=4:sample_rate=44100:duration=0" \
        \
        -c:v mpeg2video -vf "$CAPTION""format=yuva420p, hqdn3d=15" \
        -b:v $BITRATE_VIDEO -minrate:v $BITRATE_VIDEO -maxrate:v  $BITRATE_VIDEO\
        -f mpegts  -blocksize 1880 -acodec mp2 -b:a 64K -ar 44100 -ac $AUDIO_CHANNELS\
        -mpegts_original_network_id 1 -mpegts_transport_stream_id 1 \
        -mpegts_service_id $SERVICEID \
        -mpegts_pmt_start_pid $PIDPMT -streamid 0:"$PIDVIDEO" -streamid 1:"$PIDAUDIO" \
        -metadata service_provider=$CALL -metadata service_name=$CHANNEL \
        -muxrate $BITRATE_TS -y $OUTPUT &

    else
      # ******************************* MPEG-2 ANALOG VIDEO WITH AUDIO ************************************

      # PCR PID ($PIDSTART) seems to be fixed as the same as the video PID.  
      # PMT, Vid and Audio PIDs can all be set.

      sudo nice -n -30 $PATHRPI"/ffmpeg" -loglevel $MODE_DEBUG -itsoffset "$ITS_OFFSET"\
        -analyzeduration 0 -probesize 2048  -fpsprobesize 0 -thread_queue_size 512\
        -f v4l2 -framerate $VIDEO_FPS -video_size "$VIDEO_WIDTH"x"$VIDEO_HEIGHT"\
        -i $VID_USB -fflags nobuffer \
        \
        -f alsa -ac $AUDIO_CHANNELS -ar $AUDIO_SAMPLE \
        -i hw:$AUDIO_CARD_NUMBER,0 \
        \
        -c:v mpeg2video -vf "$CAPTION""format=yuva420p, hqdn3d=15" \
        -b:v $BITRATE_VIDEO -minrate:v $BITRATE_VIDEO -maxrate:v  $BITRATE_VIDEO\
        -f mpegts  -blocksize 1880 -acodec mp2 -b:a 64K -ar 44100 -ac $AUDIO_CHANNELS\
        -mpegts_original_network_id 1 -mpegts_transport_stream_id 1 \
        -mpegts_service_id $SERVICEID \
        -mpegts_pmt_start_pid $PIDPMT -streamid 0:"$PIDVIDEO" -streamid 1:"$PIDAUDIO" \
        -metadata service_provider=$CALL -metadata service_name=$CHANNEL \
        -muxrate $BITRATE_TS -y $OUTPUT &

    fi
  ;;

# ============================================ END =============================================================

# flow exits from a.sh leaving ffmpeg or avc2ts and rpidatv running
# these processes are killed by menu.sh or rpidatvgui on selection of "stop transmit"

esac
