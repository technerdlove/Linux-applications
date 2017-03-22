#!bin/bash

# Here I install nfs on an Ubuntu machine as a client to nfs on a CentOS 7 server

# Get the internal nfs server ip address from a pre-populated file (at the end openldap-server-automated.sh) and place it in /tmp/openldap-server-ip
curl -o /tmp/openldap-server-ip https://raw.githubusercontent.com/technerdlove/Linux-applications-companion/master/openldap-server-ip.txt
# Assign the ip address to a variable named "ipaddress"
ipaddress=$(cat /tmp/openldap-server-ip)

# Get ldap selections from pre-populated file
curl -o /tmp/ldap-selections https://raw.githubusercontent.com/technerdlove/Linux-applications-companion/master/ldapselections.txt

ldapselections=$(cat /tmp/ldap-selections)


# Install nfs on client (ubuntu machine)
#apt-get -y install nfs-client
export DEBIAN_FRONTEND=noninteractive
ap-get update
apt-get --yes install libnss-ldap libpam-ldap ldap-utils nslcd debconf-utils
unset DEBIAN_FRONTEND

while read url
do
  curl "$url" >> everywebpage_combined.html
done < list_of_urls.txt

while read line; do echo "$line" | debconf-set-selections; done < ldapselections

# Then check to make sure your changes made it into debconf: 
debconf-get-selections | grep ^ldap


#############
#LDAP client configuration to use LDAP Server:

# STEP 1: Install the necessary LDAP client packages on the client machine.
yum install -y openldap-clients nss-pam-ldapd

# Execute the below command to add the client machine to LDAP server for single sign on. 
# Replace “192.168.12.10” with your LDAP server’s IP address or hostname.
authconfig --enableldap --enableldapauth --ldapserver=$ipaddress --ldapbasedn="dc=technerdlove,dc=local" --enablemkhomedir --update


# Restart the LDAP client service.
systemctl restart  nslcd

# STEP 2: Verify LDAP Login:
# Use getent command to get the LDAP entries from the LDAP server.
getent passwd ann
