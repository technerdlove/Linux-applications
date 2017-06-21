#!/bin/bash

#########################################
# Here I automate an OpenLDAP install to a CentOS 7 server box

# ASSUMPTIONS:
# 1) Git repo with phpldapadmin config file is already installed on server
# 2) You have become root throughout this install.  (You need to be root to execute these commands.)
     # sudo bash openldap-server-automated.sh
# 3) Google Cloud instance with access to Google Cloud APIs (External ip address command is specific to Google Cloud).
#########################################


################################################
# STEP 0: INSTALL GIT REPOSITORY BEFORE ALL ELSE
################################################
# Your git repository will at least hold the configurations for phpldapadmin
# This automation script will call upon the git repo for the phpldapadmin config file


#########################################
# STEP 1: INSTALL ALL DEPENDENCIES
#########################################

echo "STEP 1:  We install dependencies.."
# 1-A: Install net-tools for monitoring that LDAP is installed and functioning
echo "Installing net-tools for monitoring that LDAP is installed and functioning..."
yum -y install net-tools

# 1-B: Install LDAP
echo "Installing openldap-servers... openldap-clients..."
yum -y install openldap-servers openldap-clients
#      Copy the database configuration file included with OpenLDAP to the server's data directory. 
#      Update file permissions to ensure that the file and anything else in the directory is owned by the ldap user:
echo "Copying openldap-servers database config file and updating file permissions to change ownership to user ldap..."
unalias cp
cp /usr/share/openldap-servers/DB_CONFIG.example /var/lib/ldap/DB_CONFIG
chown ldap:ldap /var/lib/ldap/*
#       Start the LDAP server and optionally enable it to start automatically whenever the system reboots:
echo "Enabling and starting the slapd service..."
systemctl start slapd.service
systemctl enable slapd.service
#        You will get the following confirmation on the screen: 
#        Created symlink from /etc/systemd/system/multi-user.target.wants/slapd.service to /usr/lib/systemd/system/slapd.service.

#        You can manually verify the LDAP.
#        Look for slapd when you enter the following command:
echo "If you see slapd in the following, LDAP was installed successfully:"
netstat -antup | grep -i 389

sleep 5

#1-C: Install Apache
echo "Installing apache..."
yum -y install httpd
#     enable and start apache
echo "Enabling and starting the httpd service..."
systemctl enable httpd
systemctl start httpd
#     allow http connection to ldap
echo "Allowing ldap to use httpd..."
setsebool -P httpd_can_connect_ldap on

sleep 3

#1-D: Install PHPLDAPADMIN
#     Install EPEL repository first
#     You need it to install phpldapadmin
#     FYI: EPEL (Extra Packages for Enterprise Linux) is open source and free community based repository project
#     It does not provide any core duplicate packages and no compatibility issues.
#     Source:  https://www.tecmint.com/how-to-enable-epel-repository-for-rhel-centos-6-5/
echo "Installing the epel-release repo..."
yum -y install epel-release
#     now install phpldapadmin
echo "Installing phpldapadmin..."
yum -y install phpldapadmin



#########################################
# STEP 2: CONFIGURE DEPENDENCIES
#########################################

echo "STEP 2:  We configure dependencies..."
# 2-A. Configure OpenLDAP server
# 2-A-i. Setup LDAP root password
echo "generate new hashed password for ldap root user and store it on the server..."
#       generate and securely store a new pw.
newsecret=$(slappasswd -g)
newhash=$(slappasswd -s "$newsecret")
echo -n "$newsecret" > /root/ldap_admin_pass
#echo -n "$newhash" > /root/ldap_admin_pass
#chmod 600 /root/ldap_admin_pass
chmod 755 /root/ldap_admin_pass

# 2-A-ii. Configure OpenLDAP server and store in config.ldif
#         Reference config.ldif
#         Here I create config.ldif
echo "Configuring ldap server and creating config.ldif..."
#         Code note:  Using double quotes in echo statement because of $newhash variable

echo "dn: olcDatabase={2}hdb,cn=config
changetype: modify
replace: olcSuffix
olcSuffix: dc=technerdlove,dc=local

dn: olcDatabase={2}hdb,cn=config
changetype: modify
replace: olcRootDN
olcRootDN: cn=Manager,dc=technerdlove,dc=local

dn: olcDatabase={2}hdb,cn=config
changetype: modify
replace: olcRootPW
olcRootPW: $newhash" > /etc/openldap/slapd.d/config.ldif

#      Set the owner and group permissions to ldap.
chown -R ldap:ldap /etc/openldap/slapd.d/config.ldif

echo "restricting ldap database authorization..."
#          Code note:  Notice that you use single quotes for the echo statement here.
#                This is because there are double quotes in the commands contained in the echo statement
#                i.e. olcAccess: {0}to * by dn.base="gidNumber=0+uidNumber=0,...
#                Single quotes print out exactly what is in the echo statement
echo 'dn: olcDatabase={1}monitor,cn=config
changetype: modify
replace: olcAccess
olcAccess: {0}to * by dn.base="gidNumber=0+uidNumber=0,cn=peercred,cn=external,cn=auth" read by dn.base="cn=Manager,dc=ldap,dc=technerdlove,dc=local" read by * none' > /etc/openldap/slapd.d/config.ldif

#         Send the configuration to the LDAP server.
ldapmodify -Y EXTERNAL -H ldapi:/// -f /etc/openldap/slapd.d/config.ldif

#2-A-iii: Create OpenLDAP certificate
echo "Create LDAP certificate and keyout..."
openssl req -new -x509 -nodes -out /etc/openldap/certs/technerdloveldapcert.pem -keyout /etc/openldap/certs/technerdloveldapkey.pem -days 365 -subj "/C=US/ST=WA/L=Seattle/O=technerdlove/OU=IT/CN=technerdlove.local"

#      Set the owner and group permissions to ldap.
chown -R ldap:ldap /etc/openldap/certs/*.pem

echo "Creating cert.ldif and adding it to ldap configuration..."
#      Create certs.ldif file to configure LDAP to use secure communication using a self-signed certificate.
#      Reference certs.ldif
echo "dn: cn=config
changetype: modify
replace: olcTLSCertificateFile
olcTLSCertificateFile: /etc/openldap/certs/technerdloveldapcert.pem

dn: cn=config
changetype: modify
replace: olcTLSCertificateKeyFile
olcTLSCertificateKeyFile: /etc/openldap/certs/technerdloveldapkey.pem" > /etc/openldap/slapd.d/certs.ldif

#      Import the configurations to LDAP server.
ldapmodify -Y EXTERNAL  -H ldapi:/// -f /etc/openldap/slapd.d/certs.ldif

echo "Verifying ldap certificate configuration..."
#      Verify the cert configuration:
slaptest -u
#      You should get the following message confirming that the verification is complete:
#      config file testing succeeded


# 2-A-iv. Set up LDAP database
echo "Copy over default database configuration file..."
#         Copy the database configuration file included with OpenLDAP to the server's data directory. 
#         Update file permissions to ensure that the file and anything else in the directory is owned by the ldap user:
unalias cp
cp /usr/share/openldap-servers/DB_CONFIG.example /var/lib/ldap/DB_CONFIG
chown ldap:ldap /var/lib/ldap/*

#         Add the cosine and nis LDAP schemas to /etc/openldap/schema.
ldapadd -Y EXTERNAL -H ldapi:/// -f /etc/openldap/schema/cosine.ldif
ldapadd -Y EXTERNAL -H ldapi:/// -f /etc/openldap/schema/nis.ldif 
ldapadd -Y EXTERNAL -H ldapi:/// -f /etc/openldap/schema/inetorgperson.ldif

#         Generate base.ldif file for your domain.
echo "Creating base group and people structure and base.ldif..."
#         Reference base.ldif

echo "dn: dc=technerdlove,dc=local
dc: technerdlove
objectClass: top
objectClass: domain

dn: cn=Manager,dc=technerdlove,dc=local
objectClass: organizationalRole
cn: Manager
description: LDAP Manager

dn: ou=People,dc=technerdlove,dc=local
objectClass: organizationalUnit
ou: People

dn: ou=Group,dc=technerdlove,dc=local
objectClass: organizationalUnit
ou: Group" >> /etc/openldap/slapd.d/base.ldif


#           Build the directory structure.
#           ldapadd command will prompt you for the password of Manager (LDAP root user).
ldapadd -x -D "cn=Manager,dc=technerdlove,dc=local" -f /etc/openldap/slapd.d/base.ldif -y /root/ldap_admin_pass


# 2-A-v. Create LDAP users:
echo "generate new hashed password for ldap user ann and store it on the server..."
#       generate and securely store a new pw.
newsecretann=$(slappasswd -g)
newhashann=$(slappasswd -s "$newsecretann")
echo -n "$newsecretann" > /root/ldap_user_pass_ann
#echo -n "$newhashann" > /root/ldap_user_pass_ann
#chmod 600 /root/ldap_user_pass_ann
chmod 755 /root/ldap_user_pass_ann

echo "Creating LDAP user ann and user-ann.ldif..."
#        Call user-ann.ldif


echo "dn: uid=ann,ou=People,dc=technerdlove,dc=local
objectClass: top
objectClass: posixAccount
objectclass: inetOrgPerson
cn: anntechnerd
uid: ann
uidNumber: 9999
gidNumber: 500
homeDirectory: /home/users/ann
loginShell: /bin/bash 
userPassword: $newhashann" >> /etc/openldap/slapd.d/user-ann.ldif


#          Use the ldapadd command with the above file to create a new user called “ann” in OpenLDAP directory.
#          Enter LDAP Password
ldapadd -x -D "cn=Manager,dc=technerdlove,dc=local" -f /etc/openldap/slapd.d/user-ann.ldif -y /root/ldap_admin_pass

#          You should get the following message:
#          adding new entry "uid=ann,ou=People,dc=technerdlove,dc=local"

#          Assign a password to the user.
#echo "Assigning password to the user..."

#ldappasswd -s password123 -W -y /root/ldap_admin_pass -D "cn=Manager,dc=technerdlove,dc=local" -x "uid=ann,ou=People,dc=technerdlove,dc=local"

sleep 3

#           Verify LDAP entries.
echo "Verifiying user ann entry..."
ldapsearch -x cn=ann -b dc=technerdlove,dc=local

# ///// TO DO
# Must capture password givien to user ann.
# Will have to use it later for client install

# Or, store in temp location (bad idea for prod)
# ldapsearch -x cn=ann -b dc=technerdlove,dc=local | grep userPassword > (git file)
# ///// END TO DO


#           Your username and an encrypted password

#           Create a test user
echo "generate new hashed password for ldap user test and store it on the server..."
#       generate and securely store a new pw.
newsecrettest=$(slappasswd -g)
newhashtest=$(slappasswd -s "$newsecrettest")
echo -n "$newsecrettest" > /root/ldap_user_pass_test
#echo -n "$newhashtest" > /root/ldap_user_pass_test
#chmod 600 /root/ldap_user_pass_test
chmod 755 /root/ldap_user_pass_test


echo "Creating LDAP user testuser and user-testuser.ldif..."

echo "dn: uid=testuser,ou=People,dc=technerdlove,dc=local
objectClass: top
objectClass: posixAccount
objectclass: inetOrgPerson
cn: Testuser
uid: testuser
uidNumber: 9998
gidNumber: 501
homeDirectory: /home/users/testuser
loginShell: /bin/bash
userPassword: $newhashtest" >> /etc/openldap/slapd.d/user-testuser.ldif

ldapadd -x -D "cn=Manager, dc=technerdlove, dc=local" -f  /etc/openldap/slapd.d/user-testuser.ldif -y /root/ldap_admin_pass 

sleep 3

#             Assign a password to the user.
#ldappasswd -s password123 -W -y /root/ldap_admin_pass -D "cn=Manager,dc=technerdlove,dc=local" -x "uid=testuser,ou=People,dc=technerdlove,dc=local"


# 2-A-vi: Create An organization
echo "Creating organization..."

echo "dn: dc=technerdlove, dc=local
dc: technerdlove
o: Tech Nerd Love
objectclass: organization
objectclass: dcObject" >> /etc/openldap/slapd.d/organization.ldif

ldapadd -x -D "cn=Manager, dc=technerdlove, dc=local" -f  /etc/openldap/slapd.d/organization.ldif -y /root/ldap_admin_pass

sleep 3


# 2-A-vii: Create Two Groups
echo "Creating admins group..."
#          Entry 1: 
echo "dn: cn=admins,ou=Group,dc=technerdlove,dc=local
cn: admins
gidnumber: 500
objectclass: posixGroup  #posixAccount is common objectClass within LDAP used to represent user entries which typically is used for for PAM and Linux/Unix Authentication.
objectclass: top" >> /etc/openldap/slapd.d/group-admins.ldif

ldapadd -x -D "cn=Manager, dc=technerdlove, dc=local" -f  /etc/openldap/slapd.d/group-admins.ldif -y /root/ldap_admin_pass

sleep 3

echo "Creating testers group..."
#            Entry 2: 
echo "dn: cn=testers,ou=Group,dc=technerdlove,dc=local
cn: testers
gidnumber: 501
objectclass: posixGroup
objectclass: top" >> /etc/openldap/slapd.d/group-testers.ldif

ldapadd -x -D "cn=Manager, dc=technerdlove, dc=local" -f  /etc/openldap/slapd.d/group-testers.ldif -y /root/ldap_admin_pass

sleep 3

#            IS THIS NECESSARY?
echo "Assigning users to groups..."

echo "dn: cn=admins,ou=Group,dc=technerdlove,dc=local
changetype: modify
add: memberuid
memberuid: ann

dn: cn=admins,ou=Group,dc=technerdlove,dc=local
changetype: modify
add: memberuid
memberuid: testuser

dn: cn=testers,ou=Group,dc=technerdlove,dc=local
changetype: modify
add: memberuid
memberuid: testuser" >> /etc/openldap/slapd.d/add-defaultuserstogroups.ldif


ldapadd -x -D "cn=Manager, dc=technerdlove, dc=local" -f  /etc/openldap/slapd.d/add-defaultuserstogroups.ldif -y /root/ldap_admin_pass

sleep 3



# Step 2-A-viii.  Secure openldap server and configure firewall
echo "Securing ldap server..."
#           Example:
#           sed 's/hello/bonjour/' greetings.txt
#           Search for SLAPD_URLS="ldapi:/// ldap:///"  and replace with SLAPD_URLS="ldapi:/// ldap:/// ldaps:///" in /etc/sysconfig/slapd
#           The flag -i.bak creates a backup copy of the original file before sed searched and replaced
#           Keeping backup copy of the original just in case the something happens while the script runs and the file gets corrupted.
sed -i.bak 's/SLAPD_URLS="ldapi:\/\/\/ ldap:\/\/\/"/SLAPD_URLS=\"ldapi:\/\/\/ ldap:\/\/\/ ldaps:\/\/\/"/g' /etc/sysconfig/slapd

#           Restart slapd
systemctl restart slapd

echo "Confirming that server is listening on port 389..."
#           Confirm server is listening on port 389
#           lsof means list of all open files belonging to all active processes.
yum -y install lsof
lsof -i :389
#           Look for ldap

sleep 5

echo "Configuring firewall for LDAP..."
#           StartTLS is the name of the standard LDAP operation for initiating TLS/SSL.
#           ldap:// + StartTLS should be directed to a normal LDAP port (normally 389)
#           Open port 389 (tcp 389) in the system's firewall to allow outside connections to the server.
#           For each command below, you shoud see the following on the screen: success
#firewall-cmd --permanent --add-port=389/tcp
firewall-cmd --zone=public --permanent --add-service=ldap
firewall-cmd --reload


# 2-A-ix. Enable LDAP logging:
echo "Enabling LDAP logging..."
#         Call enable-ldap-log
#         Configure Rsyslog to log LDAP events to log file /var/log/ldap.log.
#         FYI:  Ryslog is the default logging program on Debian and Red-Hat based systems.

#         rsyslog server side install script -- run as root on centos7 server
#         adjust rsyslog.conf to listen for tcp, udp communication by uncommenting TCP and UDP available ports

#         Find and uncomment the following to make your server listen on the udp and tcp ports.
#         [...]
#         $ModLoad imudp
#         $UDPServerRun 514

#         [...]
#         $ModLoad imtcp
#         $InputTCPServerRun 514
#         [...]

sed -ie 's/#$ModLoad imudp/$ModLoad imudp/g' /etc/rsyslog.conf
sed -ie 's/#$UDPServerRun 514/$UDPServerRun 514/g' /etc/rsyslog.conf
sed -ie 's/#$ModLoad imtcp/$ModLoad imtcp/g' /etc/rsyslog.conf
sed -ie 's/#$InputTCPServerRun 514/$InputTCPServerRun 514/g' /etc/rsyslog.conf

#        Append command to end of to /etc/rsyslog.conf file.
#        sed -i -e '$ a local4.* /var/log/ldap.log' etc/rsyslog.conf

echo "local4.* /var/log/ldap.log" >> /etc/rsyslog.conf

#        restart the rsyslog service
systemctl restart rsyslog.service

sleep 3

#         Check that rsyslog is up and running
echo "Check to see the rsyslog is up and running..."
systemctl status rsyslog

sleep 5

#        open firewall port 514 to allow tcp, udp communication

firewall-cmd --permanent --zone=public --add-port=514/tcp
firewall-cmd --permanent --zone=public --add-port=514/udp
firewall-cmd --reload

echo "Confirming that server is listening on port 514 which is where the ryslog is listening..."
#        confirm server listening on port 514
#        yum -y install net-tools  //Should have already installed
netstat -antup | grep 514

sleep 5



# 2-B. Configure Apache

#        Must create a ssl cert for apache to use with phpldapadmin
#        create apache-selfsigned cert
yum -y install mod_ssl

mkdir /etc/ssl/private
chmod 700 /etc/ssl/private
openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /etc/ssl/private/apache-selfsigned.key -subj "/C=US/ST=WA/L=Seattle/O=IT/OU=IT/CN=technerdlove.local" -out /etc/ssl/certs/apache-selfsigned.crt
openssl dhparam -out /etc/ssl/certs/dhparam.pem 2048
cat /etc/ssl/certs/dhparam.pem | tee -a /etc/ssl/certs/apache-selfsigned.crt

#         modify /etc/httpd/conf.d/ssl.conf
sed  -i '/<VirtualHost _default_:443>/a Alias \/phpldapadmin \/usr\/share\/phpldapadmin\/htdocs' /etc/httpd/conf.d/ssl.conf
sed  -i '/Alias \/phpldapadmin \/usr\/share\/phpldapadmin\/htdocs/a Alias \/ldapadmin \/usr\/share\/phpldapadmin\/htdocs' /etc/httpd/conf.d/ssl.conf
sed  -i '/Alias \/ldapadmin \/usr\/share\/phpldapadmin\/htdocs/a DocumentRoot \"\/usr\/share\/phpldapadmin\/htdocs\"' /etc/httpd/conf.d/ssl.conf
sed  -i '/DocumentRoot \"\/usr\/share\/phpldapadmin\/htdocs\"/a ServerName technerdlove.local:443' /etc/httpd/conf.d/ssl.conf

#         BEGIN The following cipher code is from the following sources:
#         https://cipherli.st/
#         and https://raymii.org/s/tutorials/Strong_SSL_Security_On_Apache2.html

#         update cypher suite
sed -i "s/SSLProtocol all -SSLv2/#SSLProtocol all -SSLv2/g" /etc/httpd/conf.d/ssl.conf
sed -i "s/SSLCipherSuite HIGH:MEDIUM:\!aNULL:\!MD5:\!SEED:\!IDEA/#SSLCipherSuite HIGH:MEDIUM:\!aNULL:\!MD5:\!SEED:\!IDEA/g" /etc/httpd/conf.d/ssl.conf

cat <<EOT>> /etc/httpd/conf.d/ssl.conf
#         Begin copied text
#         from https://cipherli.st/
#         and https://raymii.org/s/tutorials/Strong_SSL_Security_On_Apache2.html
SSLCipherSuite EECDH+AESGCM:EDH+AESGCM:AES256+EECDH:AES256+EDH
SSLProtocol All -SSLv2 -SSLv3
SSLHonorCipherOrder On
#          Disable preloading HSTS for now.  You can use the commented out header line that includes
#          the "preload" directive if you understand the implications.
#          Header always set Strict-Transport-Security "max-age=63072000; includeSubdomains; preload"
Header always set Strict-Transport-Security "max-age=63072000; includeSubdomains"
Header always set X-Frame-Options DENY
Header always set X-Content-Type-Options nosniff
#          Requires Apache >= 2.4
SSLCompression off
SSLUseStapling on
SSLStaplingCache "shmcb:logs/stapling-cache(150000)"
#          Requires Apache >= 2.4.11
#          SSLSessionTickets Off
EOT

#          edit /etc/sysconfig/slapd
#sed -i 's/SLAPD_URLS="ldapi:\/\/\/ ldap:\/\/\/"/SLAPD_URLS=\"ldapi:\/\/\/ ldap:\/\/\/ ldaps:\/\/\/"/g' /etc/sysconfig/slapd


# 2-C. Configure PHPLDAPAMIN

#           Set config file
echo "Setting login to fully qualified domain name (fqdn)..."
cp -f /tmp/Linux-applications/config.php /etc/phpldapadmin/config.php

#           allow login from the web
echo "Making ldap htdocs accessible from the web..."
cp -f /tmp/Linux-applications/config.php /etc/httpd/conf.d/config.php

#           restart slapd
systemctl restart slapd

#           restart the httpd service
systemctl restart httpd

#configure firewall to allow access

echo "Configuring the built-in firewall to allow access..."
firewall-cmd --permanent --add-port=636/tcp
firewall-cmd --permanent --zone=public --add-service=http
firewall-cmd --reload

# Check who is listening on port 636
echo "Check who is listening on port 636...is it http?"
netstat -antup | grep 636

sleep 5

#           You're done with phpldapadmin configurations.  Here is the external url for phpldapadmin
#           Note that the specific command to get the external ip address is for instances hosted in Google Cloud only

extipaddr=$(curl "http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/0/access-configs/0/external-ip" -H "Metadata-Flavor: Google")

echo "ldap configuration complete. Point your browser to http://$extipaddr/phpldapadmin to login..."

sleep 5


##################################################################################
# (FOR TESTING ONLY) STEP 3: STORE OPENLDAP SERVER INTERNAL IP ADDRESS FOR USE BY LDAP CLIENT
##################################################################################

echo "STEP 3:  We store ldap server ip address for use by ldap client..."
#         pull down git repository
#yum -y install git
git clone https://github.com/technerdlove/Linux-applications-companion.git
git config --global user.name "technerdlove"
git config --global user.email "technerdlove@gmail.com"

#         change to git directory so can execute git commands
cd Linux-applications-companion

#         Put internal ipaddress into a file in GitHub
#         If a number is already in there, overwrite it. 
hostname -i > openldap-server-ip.txt  

git add openldap-server-ip.txt
git commit -m "Populated ipaddress"
git push -f origin master # -f forces overwrite of existing content in GitHub repo
#         You will have to enter your username and password 

#         Remove the Git directory
cd ..
rm -r Linux-applications-companion
echo "Git removed"


#########################################
# YOU'RE DONE!
#########################################
#           You're done.  Here is the url for phpldapadmin
extipaddr=$(curl "http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/0/access-configs/0/external-ip" -H "Metadata-Flavor: Google")

echo "ldap configuration complete. Point your browser to http://$extipaddr/phpldapadmin to login..."
