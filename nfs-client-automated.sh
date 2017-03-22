#!bin/bash

# Here I install nfs on an Ubuntu machine as a client to nfs on a CentOS 7 server

# Get the internal nfs server ip address from a pre-populated file (at the end nfs-server-automated.sh) and place it in /tmp/nfs-server-ip
curl -o /tmp/nfs-server-ip https://raw.githubusercontent.com/technerdlove/Linux-applications-companion/master/nfs-server-ip.txt

# Assign the ip address to a variable named "ipaddress"
ipaddress=$(cat /tmp/nfs-server-ip)

# Install nfs on client (ubuntu machine)

apt-get -y install nfs-client

# Mount the nfs files from the nfs server
showmount -e $ipaddress 
mkdir /mnt/nfstest 
# To save us from retyping this after every reboot we add the following line to /etc/fstab:
echo "$ipaddress:/var/nfsshare/        /mnt/nfstest       nfs     defaults 0 0" >> /etc/fstab
mount -a

# Check to see if nfs loaded
mount | grep nfs

# Test ability to read and write
touch /mnt/nfstest/test
#If no error message, successful
