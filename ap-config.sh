#!/bin/bash
  
#set -x

# pi-ap:	These scripts configure a Raspberry Pi into a wireless Access Point
# Source:	https://github.com/f1linux/pi-ap
# Version:	01.10.02
# License:	GPL 3.0

# Script Author:        Terrence Houlahan Linux & Network Engineer
# Contact:              houlahan@F1Linux.com
# Linkedin:				www.linkedin.com/in/terrencehoulahan

set -euxo pipefail

# Do not edit below sources
source "${BASH_SOURCE%/*}/variables.sh"
source "${BASH_SOURCE%/*}/functions.sh"


# Useful wireless-tools commands:
#----------------
# iw dev



### /etc/default/crda Configuration:
# Set the AP country regulatory domain
sed -i "s/REGDOMAIN=/REGDOMAIN=$WIFIREGULATORYDOMAIN/" /etc/default/crda


echo
echo "Regulatory Domain Set: /etc/default/crda"
echo



########################### Networking: Forwarding ###########################
# NOTE: forwarding is configured in "kernel_modifications.sh" as its accomplished via sysctl interface 




######################### DHCP *CLIENT* Config: "dhcpcd5" #########################
# References:
#	https://wiki.archlinux.org/index.php/Dhcpcd
# Package "dhcpcd5" is a DHCP *CLIENT* 
#
### DHCPCD Configuration:
echo "" >> /etc/dhcpcd.conf
echo "interface $INTERFACEAP" >> /etc/dhcpcd.conf
echo "static ip_address=$IPV4IPWLAN0" >> /etc/dhcpcd.conf
echo "nohook wpa_supplicant" >> /etc/dhcpcd.conf
echo '' >> /etc/dhcpcd.conf

# Restart all the networky stuff:
systemctl restart dhcpcd.service



echo
echo "dhcpcd Configured with SED and Enabled: /etc/dhcpcd.conf"
echo

######################### Supplicant Config: "wpasupplicant" ########################
# References:
# 	http://w1.fi/cgit/hostap/plain/wpa_supplicant/README
# 	http://w1.fi/wpa_supplicant/
# 	http://w1.fi/wpa_supplicant/devel/
# 	https://help.ubuntu.com/community/WifiDocs/WPAHowTo#WPA_Supplicant
#
# Package "wpasupplicant" handles authentication from wireless clients connecting to AP

# If a wpa_supplicant ERROR MESSAGE found in the output of "tail -fn 100 /var/log/syslog" treat as a red-herring: it has no effect:
#		"Note: nl80211 driver interface is not designed to be used with ap_scan=2; this can result in connection failures"
# "Error" persists even after setting "ap_scan=1" in /etc/wpa_supplicant/wpa_supplicant.conf.
# Source: https://bugzilla.redhat.com/show_bug.cgi?id=1463245


if [ -f /etc/wpa_supplicant/wpa_supplicant.conf ]; then
	rm /etc/wpa_supplicant/wpa_supplicant.conf
fi


cat <<EOF> /etc/wpa_supplicant/wpa_supplicant.conf
ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
update_config=1
country=$WIFIREGULATORYDOMAIN
ap_scan=1

network={
        ssid="$SSIDNAME"
        psk="$APWPA2PASSWD"
}
EOF

chmod 0600 /etc/wpa_supplicant/wpa_supplicant.conf



echo
echo "Created: /etc/wpa_supplicant/wpa_supplicant.conf"
echo


usermod -G netdev -a $USEREXECUTINGSCRIPT

systemctl unmask wpa_supplicant.service
systemctl enable wpa_supplicant.service
systemctl start wpa_supplicant.service


echo
echo "Enabled and Started wpa_supplicant.service"
echo





#######  hostapd Configuration:  #######
# References:
#	https://wiki.gentoo.org/wiki/Hostapd
#	https://wiki.archlinux.org/index.php/Software_access_point
# 	https://wireless.wiki.kernel.org/en/users/documentation/hostapd
# 	http://w1.fi/wpa_supplicant/devel/


####### Create /etc/hostapd/hostapd.conf

# Copy a default config which we will modify with sed afterwards:

# Older versions of hostapd use a compressed version of the specimen "hostapd.conf" file in "/usr/share/doc/hostapd/examples".  So we need a conditionnal test
if [ -f /usr/share/doc/hostapd/examples/hostapd.conf.gz ]; then
	zcat /usr/share/doc/hostapd/examples/hostapd.conf.gz > /etc/hostapd/hostapd.conf
else
	cp /usr/share/doc/hostapd/examples/hostapd.conf /etc/hostapd/
fi



echo
echo "Created: /etc/hostapd/hostapd.conf"
echo



####### Persistently modify key directives with sed: /etc/hostapd/hostapd.conf

### SSID Directives:
sed -i "s/ssid=test/ssid=$SSIDNAME/" /etc/hostapd/hostapd.conf
sed -i "s/#utf8_ssid=1/utf8_ssid=1/" /etc/hostapd/hostapd.conf

### Network Directives:
sed -i "s/^interface=.*/interface=$INTERFACEAP/" /etc/hostapd/hostapd.conf

### Hardware Directives:
sed -i "s/# driver=hostap/driver=nl80211/" /etc/hostapd/hostapd.conf
sed -i "s/channel=.*/channel=$CHANNEL/" /etc/hostapd/hostapd.conf
sed -i "s/hw_mode=g/hw_mode=$HWMODE/" /etc/hostapd/hostapd.conf

# Only enable directive "ieee80211ac" if dependency on "hw_mode" is met in /etc/hostapd/hostapd.conf:
if [[ $MODE80211AC = '1' ]] && [[ $HWMODE = 'a' ]]; then
        sed -i "s/#ieee80211ac=1/ieee80211ac=$MODE80211AC/" /etc/hostapd/hostapd.conf
else
        echo 'Please set directive "hw_mode" to "a" in /etc/hostapd/hostapd.conf before enabling directive "ieee80211ac"'
fi


# Disable multi-antenna support: Pi only has a single WiFi antenna.
sed -i "s/#ieee80211n=1/ieee80211n=0/" /etc/hostapd/hostapd.conf
sed -i "s/#local_pwr_constraint=3/local_pwr_constraint=3/" /etc/hostapd/hostapd.conf

### Regulatory Domain Directives:
sed -i "s/#country_code=US/country_code=$WIFIREGULATORYDOMAIN/" /etc/hostapd/hostapd.conf
# 80211.d: https://en.wikipedia.org/wiki/IEEE_802.11d-2001
sed -i "s/#ieee80211d=1/ieee80211d=1/" /etc/hostapd/hostapd.conf
# 80211h is for to radar detection support and despite being required in the EU is disabled by default. So we enable it
sed -i "s/#ieee80211h=1/ieee80211h=1/" /etc/hostapd/hostapd.conf

### Access Restriction-related directives:
# auth_algs: 1=wpa 2=wep 3=both
sed -i "s/auth_algs=3/auth_algs=1/" /etc/hostapd/hostapd.conf
sed -i "s/#wpa=1/wpa=2/" /etc/hostapd/hostapd.conf
sed -i "s/#wpa=2/wpa=2/" /etc/hostapd/hostapd.conf
sed -i "s/#wpa_key_mgmt=WPA-PSK WPA-EAP/wpa_key_mgmt=WPA-PSK/" /etc/hostapd/hostapd.conf
sed -i "s/#wpa_passphrase=secret passphrase/wpa_passphrase=$APWPA2PASSWD/" /etc/hostapd/hostapd.conf
sed -i "s/#wpa_pairwise=TKIP CCMP/wpa_pairwise=TKIP/" /etc/hostapd/hostapd.conf
sed -i "s/#rsn_pairwise=CCMP/rsn_pairwise=CCMP/" /etc/hostapd/hostapd.conf


# Copy file with MAC Addresses of devices allowed to connect to AP
cp $PATHSCRIPTS/hostapd.accept /etc/
chmod 600 /etc/hostapd.accept
chown root:root /etc/hostapd.accept


if [[ $(grep [[:alnum:]] /etc/hostapd.accept) = '' ]]; then
	echo
	echo 'Please provide at least 1 MAC Address to "hostapd.accept" before enabling "macaddr_acl" directive in "/etc/hostapd/hostapd.conf"'
	echo 'Client MAC Address Whitelisting Remains DISABLED'
	echo
else
	sed -i "s/macaddr_acl=0/macaddr_acl=$MACADDRACL/" /etc/hostapd/hostapd.conf
	sed -i "s|#accept_mac_file=/etc/hostapd.accept|accept_mac_file=/etc/hostapd.accept|" /etc/hostapd/hostapd.conf
fi



echo
echo "Modified key directives with SED: /etc/hostapd/hostapd.conf"
echo



# https://bugs.debian.org/cgi-bin/bugreport.cgi?bug=380632
chmod 600 /etc/hostapd/hostapd.conf


# Configure hostapd process as daemon:
sed -i 's|#DAEMON_CONF=""|DAEMON_CONF="/etc/hostapd/hostapd.conf"|' /etc/default/hostapd

systemctl unmask hostapd
systemctl enable hostapd

echo
echo "Service hostapd unmasked and enabled"
echo




systemctl restart networking.service

# After all the fundamental config has been accomplished we finally restart hostapd:
# The required masquerading will be configured in the firewall section
systemctl start hostapd
