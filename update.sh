#!/bin/bash

# Updated by davecrump 201809051

DisplayUpdateMsg() {
# Delete any old update message image  201802040
rm /home/pi/tmp/update.jpg >/dev/null 2>/dev/null

# Create the update image in the tempfs folder
convert -size 720x576 xc:white \
    -gravity North -pointsize 40 -annotate 0 "\nUpdating Portsdown Software" \
    -gravity Center -pointsize 50 -annotate 0 "$1""\n\nPlease wait" \
    -gravity South -pointsize 50 -annotate 0 "DO NOT TURN POWER OFF" \
    /home/pi/tmp/update.jpg

# Display the update message on the desktop
sudo fbi -T 1 -noverbose -a /home/pi/tmp/update.jpg >/dev/null 2>/dev/null
(sleep 1; sudo killall -9 fbi >/dev/null 2>/dev/null) &  ## kill fbi once it has done its work
}

reset

printf "\nCommencing update.\n\n"

DisplayUpdateMsg "Step 3 of 10\nSaving Current Config\n\nXXX-------"

# Note previous version number
cp -f -r /home/pi/rpidatv/scripts/installed_version.txt /home/pi/prev_installed_version.txt

# Make a safe copy of rpidatvconfig.txt
cp -f -r /home/pi/rpidatv/scripts/rpidatvconfig.txt /home/pi/rpidatvconfig.txt >/dev/null 2>/dev/null


# If they exist, make a safe copies of portsdown_config and portsdown_presets (201802040)
if [ -f "/home/pi/rpidatv/scripts/portsdown_config.txt" ]; then
  cp -f -r /home/pi/rpidatv/scripts/portsdown_config.txt /home/pi/portsdown_config.txt
  cp -f -r /home/pi/rpidatv/scripts/portsdown_presets.txt /home/pi/portsdown_presets.txt
fi

# Make a safe copy of siggencal.txt if required (201710281)
if [ -f "/home/pi/rpidatv/src/siggen/siggencal.txt" ]; then
  cp -f -r /home/pi/rpidatv/src/siggen/siggencal.txt /home/pi/siggencal.txt
fi

# Make a safe copy of touchcal.txt if required (201711030)
if [ -f "/home/pi/rpidatv/scripts/touchcal.txt" ]; then
  cp -f -r /home/pi/rpidatv/scripts/touchcal.txt /home/pi/touchcal.txt
fi

# Make a safe copy of rtl-fm_presets.txt if required
cp -f -r /home/pi/rpidatv/scripts/rtl-fm_presets.txt /home/pi/rtl-fm_presets.txt

# Make a safe copy of portsdown_locators.txt if required
cp -f -r /home/pi/rpidatv/scripts/portsdown_locators.txt /home/pi/portsdown_locators.txt

# Make a safe copy of rx_presets.txt if required
cp -f -r /home/pi/rpidatv/scripts/rx_presets.txt /home/pi/rx_presets.txt

# Make a safe copy of the Stream Presets if required
cp -f -r /home/pi/rpidatv/scripts/stream_presets.txt /home/pi/stream_presets.txt

# Check if fbi (frame buffer imager) needs to be installed
if [ ! -f "/usr/bin/fbi" ]; then
  sudo apt-get -y install fbi
fi

DisplayUpdateMsg "Step 4 of 10\nUpdating Software Packages\n\nXXXX------"

# Uninstall the apt-listchanges package to allow silent install of ca certificates
# http://unix.stackexchange.com/questions/124468/how-do-i-resolve-an-apparent-hanging-update-process
sudo apt-get -y remove apt-listchanges

# Prepare to update the distribution (added 20170405)
sudo dpkg --configure -a
sudo apt-get clean
sudo apt-get update

DisplayUpdateMsg "Step 4a of 10\nStill Updating Software Packages\n\nXXXX------"

# Update the distribution (added 20170403)

# --------- Do not update packages until mmal and IL firmware issues are fixed ------

#sudo apt-get -y dist-upgrade  


# Check that ImageMagick is installed (201704050)
sudo apt-get -y install imagemagick

# Check that libraries required for new ffmpeg are installed (20170630)
sudo apt-get -y install libvdpau-dev libva-dev

# Check that htop is installed (201710080)
sudo apt-get -y install htop

#  Delete the duplicate touchscreen driver if it is still there (201704030)
cd /boot
sudo sed -i '/dtoverlay=ads7846/d' config.txt

# ---------- Update rpidatv -----------

DisplayUpdateMsg "Step 5 of 10\nDownloading Portsdown SW\n\nXXXXX-----"

cd /home/pi

# Check which source to download.  Default is production
# option -p or null is the production load
# option -d is development from davecrump
# option -s is staging from batc/staging
if [ "$1" == "-d" ]; then
  echo "Installing development load"
  wget https://github.com/davecrump/rpidatv/archive/master.zip -O master.zip
elif [ "$1" == "-s" ]; then
  echo "Installing BATC Staging load"
  wget https://github.com/BritishAmateurTelevisionClub/rpidatv/archive/batc_staging.zip -O master.zip
else
  echo "Installing BATC Production load"
  wget https://github.com/BritishAmateurTelevisionClub/rpidatv/archive/master.zip -O master.zip
fi

# Unzip and overwrite where we need to
unzip -o master.zip

if [ "$1" == "-s" ]; then
  cp -f -r rpidatv-batc_staging/bin rpidatv
  # cp -f -r rpidatv-batc_staging/doc rpidatv
  cp -f -r rpidatv-batc_staging/scripts rpidatv
  cp -f -r rpidatv-batc_staging/src rpidatv
  rm -f rpidatv/video/*.jpg
  cp -f -r rpidatv-batc_staging/video rpidatv
  cp -f -r rpidatv-batc_staging/version_history.txt rpidatv/version_history.txt
  rm master.zip
  rm -rf rpidatv-batc_staging
else
  cp -f -r rpidatv-master/bin rpidatv
  # cp -f -r rpidatv-master/doc rpidatv
  cp -f -r rpidatv-master/scripts rpidatv
  cp -f -r rpidatv-master/src rpidatv
  rm -f rpidatv/video/*.jpg
  cp -f -r rpidatv-master/video rpidatv
  cp -f -r rpidatv-master/version_history.txt rpidatv/version_history.txt
  rm master.zip
  rm -rf rpidatv-master
fi

DisplayUpdateMsg "Step 6 of 10\nCompiling Portsdown SW\n\nXXXXXX----"

# Compile rpidatv core
sudo killall -9 rpidatv
cd rpidatv/src
make clean
make
sudo make install

# Compile rpidatv gui
sudo killall -9 rpidatvgui
cd gui
make clean
make
sudo make install
cd ../

# Compile avc2ts
sudo killall -9 avc2ts
cd avc2ts
make clean
make
sudo make install

#install adf4351
cd /home/pi/rpidatv/src/adf4351
touch adf4351.c
make
cp adf4351 ../../bin/
cd /home/pi

## Get tstools
cd /home/pi/rpidatv/src
wget https://github.com/F5OEO/tstools/archive/master.zip
unzip master.zip
rm -rf tstools
mv tstools-master tstools
rm master.zip

## Compile tstools
cd tstools
make
cp bin/ts2es ../../bin/

#install H264 Decoder : hello_video
#compile ilcomponet first
cd /opt/vc/src/hello_pi/
sudo ./rebuild.sh

# install H264 player
cd /home/pi/rpidatv/src/hello_video
touch video.c
make
cp hello_video.bin ../../bin/

# install MPEG-2 player
cd /home/pi/rpidatv/src/hello_video2
touch video.c
make
cp hello_video2.bin ../../bin/

# Check if omxplayer needs to be installed 201807151
if [ ! -f "/usr/bin/omxplayer" ]; then
  sudo apt-get -y install omxplayer
fi

## TouchScreen GUI
## FBCP : Duplicate Framebuffer 0 -> 1
#cd /home/pi/
#wget https://github.com/tasanakorn/rpi-fbcp/archive/master.zip
#unzip master.zip
#rm -rf rpi-fbcp
#mv rpi-fbcp-master rpi-fbcp
#rm master.zip

## Compile fbcp
#cd rpi-fbcp/
#rm -rf build
#mkdir build
#cd build/
#cmake ..
#make
#sudo install fbcp /usr/local/bin/fbcp
#cd ../../

# Disable fallback IP (201701230)

cd /etc
sudo sed -i '/profile static_eth0/d' dhcpcd.conf
sudo sed -i '/static ip_address=192.168.1.60/d' dhcpcd.conf
sudo sed -i '/static routers=192.168.1.1/d' dhcpcd.conf
sudo sed -i '/static domain_name_servers=192.168.1.1/d' dhcpcd.conf
sudo sed -i '/interface eth0/d' dhcpcd.conf
sudo sed -i '/fallback static_eth0/d' dhcpcd.conf

# Disable the Touchscreen Screensaver (201701070)
cd /boot
if ! grep -q consoleblank cmdline.txt; then
  sudo sed -i -e 's/rootwait/rootwait consoleblank=0/' cmdline.txt
fi
cd /etc/kbd
sudo sed -i 's/^BLANK_TIME.*/BLANK_TIME=0/' config
sudo sed -i 's/^POWERDOWN_TIME.*/POWERDOWN_TIME=0/' config
cd /home/pi

DisplayUpdateMsg "Step 7 of 10\nCompiling Accessories\n\nXXXXXXX---"


# Delete, download, compile and install DATV Express-server (201702021)

if [ ! -f "/bin/netcat" ]; then
  sudo apt-get -y install netcat
fi

sudo rm -f -r /lib/firmware/datvexpress
sudo rm -f /usr/bin/express_server
sudo rm -f /etc/udev/rules.d/10-datvexpress.rules
sudo rm -f -r /home/pi/express_server-master
cd /home/pi
wget https://github.com/G4GUO/express_server/archive/master.zip -O master.zip
sudo rm -f -r express_server-master
unzip -o master.zip
sudo rm -f -r express_server
mv express_server-master express_server
rm master.zip
cd /home/pi/express_server
make
sudo make install
cd /home/pi

# Update pi-sdn with less trigger-happy version (201705200)
rm -fr /home/pi/pi-sdn /home/pi/pi-sdn-build/
git clone https://github.com/philcrump/pi-sdn /home/pi/pi-sdn-build
cd /home/pi/pi-sdn-build
make
mv pi-sdn /home/pi/
cd /home/pi

DisplayUpdateMsg "Step 8 of 10\nRestoring Config\n\nXXXXXXXX--"

# Update the call to pi-sdn if it is enabled (201702020)
if [ -f /home/pi/.pi-sdn ]; then
  rm -f /home/pi/.pi-sdn
  cp /home/pi/rpidatv/scripts/configs/text.pi-sdn /home/pi/.pi-sdn
fi

# Restore or update portsdown_config.txt 20180204

if [ -f "/home/pi/portsdown_config.txt" ]; then  ## file exists, so restore it
  cp -f -r /home/pi/portsdown_config.txt /home/pi/rpidatv/scripts/portsdown_config.txt
  cp -f -r /home/pi/portsdown_presets.txt /home/pi/rpidatv/scripts/portsdown_presets.txt
else           ## file does not exist, so copy relavent items from rpidatvconfig.txt
  source /home/pi/rpidatv/scripts/copy_config.sh
fi
## rm -f /home/pi/rpidatvconfig.txt
rm -f /home/pi/portsdown_config.txt
rm -f /home/pi/portsdown_presets.txt
rm -f /home/pi/rpidatv/scripts/copy_config.sh

if ! grep -q modulation /home/pi/rpidatv/scripts/portsdown_config.txt; then
  # File needs updating
  printf "Adding new entries to user's portsdown_config.txt\n"
  # Delete any blank lines
  sed -i -e '/^$/d' /home/pi/rpidatv/scripts/portsdown_config.txt
  # Add the 2 new entries and a new line 
  echo "modulation=DVB-S" >> /home/pi/rpidatv/scripts/portsdown_config.txt
  echo "limegain=90" >> /home/pi/rpidatv/scripts/portsdown_config.txt
  echo "" >> /home/pi/rpidatv/scripts/portsdown_config.txt
fi

if ! grep -q d1limegain /home/pi/rpidatv/scripts/portsdown_presets.txt; then
  # File needs updating
  printf "Adding new entries to user's portsdown_presets.txt\n"
  # Delete any blank lines
  sed -i -e '/^$/d' /home/pi/rpidatv/scripts/portsdown_presets.txt
  # Add the 9 new entries and a new line 
  echo "d1limegain=90" >> /home/pi/rpidatv/scripts/portsdown_presets.txt
  echo "d2limegain=90" >> /home/pi/rpidatv/scripts/portsdown_presets.txt
  echo "d3limegain=90" >> /home/pi/rpidatv/scripts/portsdown_presets.txt
  echo "d4limegain=90" >> /home/pi/rpidatv/scripts/portsdown_presets.txt
  echo "d5limegain=90" >> /home/pi/rpidatv/scripts/portsdown_presets.txt
  echo "t1limegain=90" >> /home/pi/rpidatv/scripts/portsdown_presets.txt
  echo "t2limegain=90" >> /home/pi/rpidatv/scripts/portsdown_presets.txt
  echo "t3limegain=90" >> /home/pi/rpidatv/scripts/portsdown_presets.txt
  echo "t4limegain=90" >> /home/pi/rpidatv/scripts/portsdown_presets.txt
  echo "" >> /home/pi/rpidatv/scripts/portsdown_presets.txt
fi

# Install Waveshare 3.5B DTOVERLAY if required (201704080)
if [ ! -f /boot/overlays/waveshare35b.dtbo ]; then
  sudo cp /home/pi/rpidatv/scripts/waveshare35b.dtbo /boot/overlays/
fi

# Load new .bashrc to source the startup script at boot and log-on (201704160)
cp -f /home/pi/rpidatv/scripts/configs/startup.bashrc /home/pi/.bashrc

# Always auto-logon and run .bashrc (and hence startup.sh) (201704160)
sudo ln -fs /etc/systemd/system/autologin@.service\
 /etc/systemd/system/getty.target.wants/getty@tty1.service

# Reduce the dhcp client timeout to speed off-network startup (201704160)
# If required
if ! grep -q timeout /etc/dhcpcd.conf; then
  sudo bash -c 'echo -e "\n# Shorten dhcpcd timeout from 30 to 15 secs" >> /etc/dhcpcd.conf'
  sudo bash -c 'echo -e "timeout 15\n" >> /etc/dhcpcd.conf'
fi

# Enable the Video output in PAL mode (201707120)
cd /boot
sudo sed -i 's/^#sdtv_mode=2/sdtv_mode=2/' config.txt
cd /home/pi

# Compile and install the executable for switched repeater streaming (201708150)
cd /home/pi/rpidatv/src/rptr
make
mv keyedstream /home/pi/rpidatv/bin/
cd /home/pi

# Compile and install the executable for GPIO-switched transmission (201710080)
cd /home/pi/rpidatv/src/keyedtx
make
mv keyedtx /home/pi/rpidatv/bin/
cd /home/pi

# Check if tmpfs at ~/tmp exists.  If not,
# amend /etc/fstab to create a tmpfs drive at ~/tmp for multiple images (201708150)
if [ ! -d /home/pi/tmp ]; then
  sudo sed -i '4itmpfs           /home/pi/tmp    tmpfs   defaults,noatime,nosuid,size=10m  0  0' /etc/fstab
fi

# Check if ~/snaps folder exists for captured images.  Create if required
# and set the snap index number to zero. (201708150)
if [ ! -d /home/pi/snaps ]; then
  mkdir /home/pi/snaps
  echo "0" > /home/pi/snaps/snap_index.txt
fi

# Compile and install the executable for the Stream Receiver (201807290)
cd /home/pi/rpidatv/src/streamrx
make
mv streamrx /home/pi/rpidatv/bin/
cd /home/pi

# Compile the Signal Generator (201710280)
cd /home/pi/rpidatv/src/siggen
make clean
make
sudo make install
cd /home/pi

# Compile the Attenuator Driver (201801060)
cd /home/pi/rpidatv/src/atten
make
cp /home/pi/rpidatv/src/atten/set_attenuator /home/pi/rpidatv/bin/set_attenuator
cd /home/pi

# Restore the user's original siggencal.txt if required (re-commented after 201801062)
#if [ -f "/home/pi/siggencal.txt" ]; then
#  cp -f -r /home/pi/siggencal.txt /home/pi/rpidatv/src/siggen/siggencal.txt
#fi

# Restore the user's original touchcal.txt if required (201711030)
if [ -f "/home/pi/touchcal.txt" ]; then
  cp -f -r /home/pi/touchcal.txt /home/pi/rpidatv/scripts/touchcal.txt
fi

# Restore the user's original rtl-fm_presets.txt if required
if [ -f "/home/pi/rtl-fm_presets.txt" ]; then
  cp -f -r /home/pi/rtl-fm_presets.txt /home/pi/rpidatv/scripts/rtl-fm_presets.txt
fi

# Restore the user's original portsdown_locators.txt if required
if [ -f "/home/pi/portsdown_locators.txt" ]; then
  cp -f -r /home/pi/portsdown_locators.txt /home/pi/rpidatv/scripts/portsdown_locators.txt
else
  # Over-write the default locator with the user's locator
  source /home/pi/rpidatv/scripts/copy_locator.sh
fi

# Restore the user's original rx_presets.txt if required
if [ -f "/home/pi/rx_presets.txt" ]; then
  cp -f -r /home/pi/rx_presets.txt /home/pi/rpidatv/scripts/rx_presets.txt
fi

# Restore the user's original stream presets if required
if [ -f "/home/pi/stream_presets.txt" ]; then
  cp -f -r /home/pi/stream_presets.txt /home/pi/rpidatv/scripts/stream_presets.txt
fi

DisplayUpdateMsg "Step 9 of 10\nInstalling FreqShow SW\n\nXXXXXXXXX-"

# Either install FreqShow, or downgrade sdl so that it works (20180101)
if [ -f "/home/pi/FreqShow/LICENSE" ]; then
  # Freqshow has already been installed, so downgrade the sdl version
  sudo dpkg -i /home/pi/rpidatv/scripts/configs/freqshow/libsdl1.2debian_1.2.15-5_armhf.deb
  # Delete the old FreqShow version
  rm -fr /home/pi/FreqShow/
  # Download FreqShow
  git clone https://github.com/adafruit/FreqShow.git
  # Change the settings for our environment
  rm /home/pi/FreqShow/freqshow.py
  cp /home/pi/rpidatv/scripts/configs/freqshow/waveshare_freqshow.py /home/pi/FreqShow/freqshow.py
  rm /home/pi/FreqShow/model.py
  cp /home/pi/rpidatv/scripts/configs/freqshow/waveshare_146_model.py /home/pi/FreqShow/model.py
else
  # Start the install from scratch
  sudo apt-get -y install python-pip pandoc python-numpy pandoc python-pygame gdebi-core
  sudo pip install pyrtlsdr
  # Load the old (1.2.15-5) version of sdl.  Later versions do not work
  sudo gdebi --non-interactive /home/pi/rpidatv/scripts/configs/freqshow/libsdl1.2debian_1.2.15-5_armhf.deb
  # Load touchscreen configuration
  sudo cp /home/pi/rpidatv/scripts/configs/freqshow/waveshare_pointercal /etc/pointercal
  # Download FreqShow
  git clone https://github.com/adafruit/FreqShow.git
  # Change the settings for our environment
  rm /home/pi/FreqShow/freqshow.py
  cp /home/pi/rpidatv/scripts/configs/freqshow/waveshare_freqshow.py /home/pi/FreqShow/freqshow.py
  rm /home/pi/FreqShow/model.py
  cp /home/pi/rpidatv/scripts/configs/freqshow/waveshare_146_model.py /home/pi/FreqShow/model.py
fi

# Update the version number
rm -rf /home/pi/rpidatv/scripts/installed_version.txt
cp /home/pi/rpidatv/scripts/latest_version.txt /home/pi/rpidatv/scripts/installed_version.txt
cp -f -r /home/pi/prev_installed_version.txt /home/pi/rpidatv/scripts/prev_installed_version.txt
rm -rf /home/pi/prev_installed_version.txt

DisplayUpdateMsg "Step 10 of 10\nRebooting\n\nXXXXXXXXXX"
printf "\nRebooting\n"
sleep 1
sudo reboot now

exit
