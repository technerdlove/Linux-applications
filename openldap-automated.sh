#/bin/bash
# Here I automate an OpenLDAP install to a CentOS 7 box

# Become root throughout this install
sudo su

# Install Git repostitory
yum -y install git
git clone https://github.com/technerdlove/Linux-applications.git


#Install LDAP
yum -y install openldap-servers openldap-clients


# Start the LDAP server and optionally enable it to start automatically whenever the system reboots:
systemctl start slapd.service
systemctl enable slapd.service

# You will get the following confirmation on the screen: 
# Created symlink from /etc/systemd/system/multi-user.target.wants/slapd.service to /usr/lib/systemd/system/slapd.service.

# You can manually verify the LDAP.
# Look for slapd when you enter the following command:
# netstat -antup | grep -i 389

# STEP B. SETUP LDAP ROOT PASSWORD: 
# NEED TO ENTER SCRIPT HERE THAT WILL AUTOMATICALLY ASSIGN A PASSWORD
# generate and securely store a new pw.
newsecret=$(slappasswd -g)
newhash=$(slappasswd -s "$newsecret")
echo -n "$newsecret" > /root/ldap_admin_pass
chmod 0600 /root/ldap_admin_pass

# STEP C. CONFIGURE OPENLDAP SERVER
# Reference config.ldif
# Here I create config.ldif
echo "dn: olcDatabase={2}hdb,cn=config
changetype: modify
replace: olcSuffix
olcSuffix: dc=technerdlove,dc=local

dn: olcDatabase={2}hdb,cn=config
replace: olcRootDN
olcRootDN: cn=Manager,dc=technerdlove,dc=local

dn: olcDatabase={2}hdb,cn=config
changetype: modify
replace: olcRootPW
olcRootPW: $newhash

dn: olcDatabase={1}monitor,cn=config
changetype: modify
replace: olcAccess
olcAccess: {0}to * by dn.base="gidNumber=0+uidNumber=0,cn=peercred,cn=external,cn=auth" read by dn.base="cn=Manager,dc=ldap,dc=technerdlove,dc=local" read by * none" >> config.ldif

# Send the configuration to the LDAP server.
ldapmodify -Y EXTERNAL -H ldapi:/// -f config.ldif

# STEP D: CREATE LDAP CERTIFICATE 
openssl req -new -x509 -nodes -out /etc/openldap/certs/technerdloveldapcert.pem -keyout /etc/openldap/certs/technerdloveldapkey.pem -days 365 -subj "/C=US/ST=WA/L=Seattle/O=technerdlove/OU=IT/CN=technerdlove.local"

# Set the owner and group permissions to ldap.
chown -R ldap:ldap /etc/openldap/certs/*.pem

# Create certs.ldif file to configure LDAP to use secure communication using a self-signed certificate.
# Reference certs.ldif

echo "dn: cn=config
changetype: modify
replace: olcTLSCertificateFile
olcTLSCertificateFile: /etc/openldap/certs/technerdloveldapcert.pem

dn: cn=config
changetype: modify
replace: olcTLSCertificateKeyFile
olcTLSCertificateKeyFile: /etc/openldap/certs/technerdloveldapkey.pem" > certs.ldif

# Import the configurations to LDAP server.
ldapmodify -Y EXTERNAL  -H ldapi:/// -f certs.ldif

# Verify the configuration:
slaptest -u

# You should get the following message confirms the verification is complete.
# config file testing succeeded

# STEP E: SET UP LDAP DATABASE
# Copy the database configuration file included with OpenLDAP to the server's data directory. 
# Update file permissions to ensure that the file and anything else in the directory is owned by the ldap user:
unalias cp
cp /usr/share/openldap-servers/DB_CONFIG.example /var/lib/ldap/DB_CONFIG
chown ldap:ldap /var/lib/ldap/*

# Add the cosine and nis LDAP schemas to /etc/openldap/schema.
ldapadd -Y EXTERNAL -H ldapi:/// -f /etc/openldap/schema/cosine.ldif
ldapadd -Y EXTERNAL -H ldapi:/// -f /etc/openldap/schema/nis.ldif 
ldapadd -Y EXTERNAL -H ldapi:/// -f /etc/openldap/schema/inetorgperson.ldif

# Generate base.ldif file for your domain.
# Reference base.ldif

echo "dn: dc=technerdlove,dc=local
dc: technerdlove
objectClass: top
objectClass: domain

dn: cn=Manager ,dc=technerdlove,dc=local
objectClass: organizationalRole
cn: Manager
description: LDAP Manager

dn: ou=People,dc=technerdlove,dc=local
objectClass: organizationalUnit
ou: People

dn: ou=Group,dc=technerdlove,dc=local
objectClass: organizationalUnit
ou: Group" > base.ldif

# Build the directory structure.
# ldapadd command will prompt you for the password of Manager (LDAP root user).
ldapadd -x -W -D "cn=Manager,dc=technerdlove,dc=local" -f base.ldif -y /root/ldap_admin_pass


# STEP F: Create LDAP user:
# Call user-ann.ldif

echo "dn: uid=bob,ou=People,dc=technerdlove,dc=local
objectClass: top
objectClass: account
objectClass: posixAccount
objectClass: shadowAccount
cn: ann
uid: ann
uidNumber: 9999
gidNumber: 100
homeDirectory: /home/ann
loginShell: /bin/bash
gecos: Ann [Admin (at) technerdlove]
userPassword: {crypt}x
shadowLastChange: 17058
shadowMin: 0
shadowMax: 99999
shadowWarning: 7" > user-ann.ldif

# Use the ldapadd command with the above file to create a new user called “ann” in OpenLDAP directory.
# Enter LDAP Password
ldapadd -x -W -D "cn=Master,dc=technerdlove,dc=local" -f user-ann.ldif -y /root/ldap_admin_pass

# You should get the following message:
# adding new entry "uid=ann,ou=People,dc=technerdlove,dc=local"

# Assign a password to the user.
ldappasswd -s password123 -W -D "cn=Master,dc=technerdlove,dc=local" -x "uid=ann,ou=People,dc=technerdlove,dc=local"

# Verify LDAP entries.
ldapsearch -x cn=ann -b dc=technerdlove,dc=local

# STEP G: Firewall:
# Open port 389 (tcp 389) in the system's firewall to allow outside connections to the server.
# For each command below, you shoud see the following on the screen: success
echo "firewall-cmd --zone=public --permanent --add-service=ldap"
echo "firewall-cmd --reload"

# STEP H: Enable LDAP logging:
# Call enable-ldap-log


# STEP I: PHPLDAPAMIN
# Tell SE linux what's going on, so that it doesn't freek
setsebool -P httpd_can_connect_ldap on

systemctl enable httpd
systemctl start httpd

# Configure phpldapadmin.conf

sed -i 's,Require local,#Require local\n    Require all granted,g' /etc/httpd/conf.d/phpldapadmin.conf

cp NTI-310/config/config.php /etc/phpldapadmin/config.php
chown ldap:apache /etc/phpldapadmin/config.php

systemctl restart httpd.service

echo "phpldapadmin is now up and running"
