#!bin/bash

# Here I install nfs version 4, known as NFSv4 

# YOU MUST BE ROOT TO EXECUTE
# sudo su
# sudo bash nfs-server-automated.sh

#///TO DO
# Create separate script that:
# pulls down install script from GitHub 
# changes permission to executable
# Initiates the script on command line: sudo bash (path to install script)
#/// END TO DO

# 1. Install the appropriate packages:
yum -y install nfs-utils libnfsidmap

# 2. Create a globally accessible directory which will serve as the root of the file share:
#    Change permissions to wide open for the top directory and its subdirectories (regressively change permission)
mkdir /var/nfsshare 
chmod -R 777 /var/nfsshare/

# 3. Open /etc/exports - 
#    /etc/exports is the configuration file that manages which filesystems are exported and how.
#    Add an entry that identifies the directory we want to export by NFS
#    followed by which clients they are exported to and the options that govern how the export will be treated
#    Here the entry is exported to everyone (*)
# WATCH OUT:
# The exports file is very picky. 
# Make sure there's no space between the network and the parenthesized 
# options as well as no spaces around the commas that separate the options.
echo "/var/nfsshare/ *(rw,sync,no_all_squash)" >> /etc/exports


# 4. Start the necessary services and register them so that they will start when the server boots:
#    The rpcbind server converts RPC program numbers into universal addresses.
#    nfs-server starts the NFS server and the appropriate RPC processes to service requests for shared NFS file systems. It enables the clients to access NFS shares.
#    nfs-lock is a mandatory service that starts the appropriate RPC processes to allow NFS clients to lock files on the server.
#    nfs-idmap translates user and group ids into names
systemctl enable rpcbind
systemctl enable nfs-server 
systemctl enable nfs-lock 
systemctl enable nfs-idmap 
systemctl start rpcbind
systemctl start nfs-server
systemctl start nfs-lock
systemctl start nfs-idmap

# 5. Open ports 111, 2048, and 2049 in the firewall to allow traffic through:
# EXPLANATION:
# NFS relies on a few other services, which is why we also enabled rpcbind and opened firewall ports for rpcbind and mountd. 
# NFS works on top of the Remote Procedure Call (RPC) protocol, 
# and rcpind is responsible for mapping the RPC-based services to their ports. 
# An incoming connection from a client first hits the rpcbind service, providing an RPC identifier. 
# Rpcbind resolves the identifier to a particular service (NFS in this case) and redirects the client to the appropriate port. 
# There, mountd handles the request to determine whether the requested share is exported and whether the client is allowed to access it.
firewall-cmd --permanent --zone public --add-service rpc-bind
firewall-cmd --permanent --zone public --add-service mountd
firewall-cmd --permanent --zone public --add-service nfs
firewall-cmd --reload
systemctl restart nfs-server


# 6. Save ipaddress of server offset for access by openldap clients
#    pull down git repository
yum -y install git
git clone https://github.com/technerdlove/Linux-applications-companion.git

# change to git directory so can execute git commands
cd Linux-applications-companion

# Put internal ipaddress into a file in GitHub
# If a number is already in there, overwrite it. 
hostname -i > nfs-server-ip.txt  

git add nfs-server-ip.txt
git commit -m "Populated ipaddress"
git push -f origin master # -f forces overwrite of existing content in GitHub repo
# You will have to enter your username and password 

# Remove the Git directory
cd..
rm -r Linux-applications-companion
echo "Git removed"

# 7. Secure openldap server
# Example:
#sed 's/hello/bonjour/' greetings.txt
# Search for SLAPD_URLS="ldapi:/// ldap:///"  and replace with SLAPD_URLS="ldapi:/// ldap:/// ldaps:///" in /etc/sysconfig/slapd
sed -i.bak 's/SLAPD_URLS="ldapi:/// ldap:///"/SLAPD_URLS="ldapi:/// ldap:/// ldaps:///"/' /etc/sysconfig/slapd

# Restart slapd
systemctl restart slapd




