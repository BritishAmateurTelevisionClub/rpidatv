![rpidatv banner](/doc/img/Portsdown3.jpg)
# rpidatv

**rpidatv** is a DVB-S digital television transmitter for Raspberry Pi 3.  The core of the transmitter was written by Evariste Courjaud F5OEO and is maintained by him.  This BATC Version, known as the Portsdown Transmitter, has been developed by a team of BATC members for use with an external synthesized oscillator and modulator/filter board to produce a signal suitable for driving a high power amateur television transmitter on the 146, 432 or 1296 MHz bands.  The idea is that the design should be reproducible by someone who has never used Linux before.  Detailed instructions on loading the software are listed below, and further details of the complete transmitter design and build are on the BATC Wiki at https://wiki.batc.tv/The_Portsdown_Transmitter.  There is a Forum for discussion of the project here: http://www.batc.org.uk/forum/viewforum.php?f=103

Our thanks to Evariste and all the other contributors to this community project.  All code within the project is GPL.

# Installation for BATC Portsdown Transmitter Version

The preferred installation method only needs a Windows PC connected to the same (internet-connected) network as your Raspberry Pi.  Do not connect a keyboard or HDMI display directly to your Raspberry Pi.

- First download the 10 April 2017 release of Raspbian Jessie Lite on to your Windows PC from here http://downloads.raspberrypi.org/raspbian_lite/images/raspbian_lite-2017-04-10/2017-04-10-raspbian-jessie-lite.zip.  

- Unzip the image and then transfer it to a Micro-SD Card using Win32diskimager https://sourceforge.net/projects/win32diskimager/

- Before you remove the card from your Windows PC, look at the card with windows explorer; the volume should be labelled "boot".  Create a new empty file called ssh in the top-level (root) directory by right-clicking, selecting New, Text Document, and then change the name to ssh (not ssh.txt).  You should get a window warning about changing the filename extension.  Click OK.  If you do not get this warning, you have created a file called ssh.txt and you need to rename it ssh.  IMPORTANT NOTE: by default, Windows (all versions) hides the .txt extension on the ssh file.  To change this, in Windows Explorer, select File, Options, click the View tab, and then untick "Hide extensions for known file types". Then click OK.

- If you have a Pi Camera and/or touchscreen display, you can connect them now.  Power up the RPi with the new card inserted, and a network connection.  Do not connect a keyboard or HDMI display to the Raspberry Pi. 

- Find the IP address of your Raspberry Pi using an IP Scanner (such as Advanced IP Scanner http://filehippo.com/download_advanced_ip_scanner/ for Windows, or Fing on an iPhone) to get the RPi's IP address 

- From your windows PC use Putty (http://www.chiark.greenend.org.uk/~sgtatham/putty/download.html) to log in to the IP address that you noted earlier.  You will get a Security warning the first time you try; this is normal.

- Log in (user: pi, password: raspberry) then cut and paste the following code in, one line at a time:

```sh
wget https://raw.githubusercontent.com/BritishAmateurTelevisionClub/rpidatv/master/install.sh
chmod +x install.sh
./install.sh
```

As of April 2017, you should not need to answer any questions during the installation.  However, the installation takes a little longer as the operating system is brought fully up-to-date.

- If your ISP is Virgin Media and you receive an error after entering the wget line: 'GnuTLS: A TLS fatal alert has been received.', it may be that your ISP is blocking access to GitHub.  If (only if) you get this error with Virgin Media, paste the following command in, and press return.
```sh
sudo sed -i 's/^#name_servers.*/name_servers=8.8.8.8/' /etc/resolvconf.conf
```
Then reboot, and try again.  The command asks your RPi to use Google's DNS, not your ISP's DNS.

- If your ISP is BT, you will need to make sure that "BT Web Protect" is disabled so that you are able to download the software.

- For French menus and keyboard, replace the last line above with 
```sh
./install.sh fr
```

- When it has finished, accept the reboot offered or type "sudo reboot now".  After restart, the Touchscreen should display a BATC Logo and the Pi's IP Address; log in again and the console menu should be displayed on your PC.  If not, you can start the console menu by typing:

```sh
/home/pi/rpidatv/scripts/menu.sh menu
```

Note that you do not need to load any touchscreen drivers - if the touchscreen does not work try powering off and on again.  If your touchscreen appears as if the touch sense is 90 degrees out, try selecting the TonTec display in the Setup menu.  If the colours seem wrong, try selecting the Waveshare Type B display and rebooting.

After initial installation, on selecting transmit, the RPi is configured to generate a direct RF output (from GPIO pin 32) on 437 MHz at 333KS using the BATC Logo image as the source.  

Advanced notes:  To load the development and staging versions, use the following lines:
```sh
wget https://raw.githubusercontent.com/davecrump/rpidatv/master/install.sh  #OR#
wget https://raw.githubusercontent.com/BritishAmateurTelevisionClub/rpidatv/batc_staging/install.sh
chmod +x install.sh
./install.sh -d    #OR#
./install.sh -s
```
