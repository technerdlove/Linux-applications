#!bin/bash

# Here I install nfs on an Ubuntu machine as a client to nfs on a CentOS 7 server

# Get the internal nfs server ip address from a pre-populated file (at the end openldap-server-automated.sh) and place it in /tmp/openldap-server-ip
curl -o /tmp/openldap-server-ip https://raw.githubusercontent.com/technerdlove/Linux-applications-companion/master/openldap-server-ip.txt
# Assign the ip address to a variable named "ipaddress"
ipaddress=$(cat /tmp/openldap-server-ip)

# Get ldap selections from pre-populated file and store in /tmp directory under the name ldap-selections
curl -o /tmp/ldap-selections https://raw.githubusercontent.com/technerdlove/Linux-applications-companion/master/ldapselections.txt
# Assign the ldap selections file to a variable named "ldapselections"
ldapselections=$(cat /tmp/ldap-selections)

sleep 3

# Install nfs on client (ubuntu machine)
#apt-get -y install nfs-client
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get --yes install libnss-ldap libpam-ldap ldap-utils nslcd debconf-utils
unset DEBIAN_FRONTEND


# Set ldap selections in debconf usine variable ldapselections
while read line; do echo "$line" | debconf-set-selections; done < $ldapselections

sleep 3

# Then check to make sure your changes made it into debconf: 
debconf-get-selections | grep ^ldap

sleep 3

# Manually configure files not managed by debconf: /etc/nsswitch.conf and /etc/ldap/ldap.conf
# edit /etc/ldap/ldap.conf  to append the values to the end 
# The BASE and URI values are commented out in the default set up, so easier to append than trying to automate uncommenting and replacing them)
echo "TLS_REQCERT      allow
BASE   dc=technerdlove,dc=local
URI    ldaps://$ipaddress:636" >> /etc/ldap/ldap.conf

#edit the /etc/nsswitch.conf file by adding "ldap"
sed -i 's,passwd:         compat,passwd:         ldap compat,g' /etc/nsswitch.conf
sed -i 's,group:          compat,group:          ldap compat,g' /etc/nsswitch.conf
sed -i 's,shadow:         compat,shadow:         ldap compat,g' /etc/nsswitch.conf


echo "session required                        pam_mkhomedir.so skel=/etc/skel umask=077" >> /etc/pam.d/common-session


# To complete your ldap install configuration, you'll need to set values for ldap-auth-config and nslcd
# set nslcd
echo "tls_reqcert allow" >> /etc/nslcd.conf

# restart nslcd 
#/etc/init.d/nslcd restart
service nslcd restart

sleep 3


#edit the sudoers file to give access to the admin group in ldap
#visudo

#comment out this line
sed -i 's,%admin=(ALL) ALL,#%admin ALL=(ALL) ALL,g' /etc/sudoers    #---use sed command

sleep 3

#adjust the ssh config file for the ubuntu-desktop instance /etc/ssh/sshd_config
#vi /etc/ssh/sshd_config #---use sed command
#comment out these two lines

#PasswordAuthentication no
sed -i 's,PasswordAuthentication no,#PasswordAuthentication no,g' /etc/ssh/sshd_config
#ChallengeResponseAuthentication no
sed -i 's,ChallengeResponseAuthentication no,#ChallengeResponseAuthentication no,g' /etc/ssh/sshd_config

#restart the sshd service
systemctl restart sshd.service

#login as ldap user on the ubuntu-desktop!
#command from terminal: ssh <username>@<ubuntuIPaddress>


#  Verify LDAP Login:
# Use getent command to get the LDAP entries from the LDAP server.
getent passwd ann

# Your client should be securly configured now. You can test your configuration using ldapsearch:

ldapsearch  -b "dc=technerdlove,dc=local"  -x -d 1 2>> output.txt
####
