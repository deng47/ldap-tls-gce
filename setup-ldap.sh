#!/bin/bash
#
# setup_ldap.sh - a bash shell script that set up a ldap server on a google cloud compute engine and encrypt the LDAP connection with tls
#
# requirement - for CentOS 7 only
#

error() {
    # out put error message and exit 1
    echo "ERROR: $*" 1>&2
    exit 1
}

# check OS
grep -q "CentOS Linux release 7" /etc/redhat-release || error "This script is for CentOS 7 only"

# get the internal fully qualified domain name
fully_qualified_domain_name=$(grep internal /etc/hosts | grep -v metadata.google.internal | cut -d' ' -f2)

# check if it's running on a google cloud compute engine
[ "$fully_qualified_domain_name" ] || error "This script should be run on a google cloud compute engine"

OIFS="$IFS"
IFS="."
set -- $fully_qualified_domain_name
base_DN="dc=$2,dc=$3,dc=$4"
relative_DN=$2
organization="$2 $3 $4"
password=$PASSWORD
IFS="$OIFS"

yum -y install openldap-servers openldap-clients net-tools httpd || error "Failed to install dependencies"

cp /usr/share/openldap-servers/DB_CONFIG.example /var/lib/ldap/DB_CONFIG 
chown ldap. /var/lib/ldap/DB_CONFIG 
systemctl start slapd 
systemctl enable slapd 

password_hash=$(slappasswd -s $password -n)

cat > chrootpw.ldif <<-EOF
dn: olcDatabase={0}config,cn=config
changetype: modify
add: olcRootPW
olcRootPW: $password_hash
EOF
ldapadd -Y EXTERNAL -H ldapi:/// -f chrootpw.ldif 
ldapadd -Y EXTERNAL -H ldapi:/// -f /etc/openldap/schema/cosine.ldif 
ldapadd -Y EXTERNAL -H ldapi:/// -f /etc/openldap/schema/nis.ldif 
ldapadd -Y EXTERNAL -H ldapi:/// -f /etc/openldap/schema/inetorgperson.ldif 

cat > chdomain.ldif <<-EOF
dn: olcDatabase={1}monitor,cn=config
changetype: modify
replace: olcAccess
olcAccess: {0}to * by dn.base="gidNumber=0+uidNumber=0,cn=peercred,cn=external,cn=auth"
  read by dn.base="cn=Manager,$base_DN" read by * none

dn: olcDatabase={2}hdb,cn=config
changetype: modify
replace: olcSuffix
olcSuffix: $base_DN

dn: olcDatabase={2}hdb,cn=config
changetype: modify
replace: olcRootDN
olcRootDN: cn=Manager,$base_DN

dn: olcDatabase={2}hdb,cn=config
changetype: modify
add: olcRootPW
olcRootPW: $password_hash

dn: olcDatabase={2}hdb,cn=config
changetype: modify
add: olcAccess
olcAccess: {0}to attrs=userPassword,shadowLastChange by
  dn="cn=Manager,$base_DN" write by anonymous auth by self write by * none
olcAccess: {1}to dn.base="" by * read
olcAccess: {2}to * by dn="cn=Manager,$base_DN" write by * read
EOF

ldapmodify -Y EXTERNAL -H ldapi:/// -f chdomain.ldif 


cat > basedomain.ldif <<-EOF
dn: $base_DN
objectClass: top
objectClass: dcObject
objectclass: organization
o: $organization
dc: $relative_DN

dn: cn=Manager,$base_DN
objectClass: organizationalRole
cn: Manager
description: Directory Manager

dn: ou=People,$base_DN
objectClass: organizationalUnit
ou: People

dn: ou=Group,$base_DN
objectClass: organizationalUnit
ou: Group
EOF

ldapadd -w $password -x -D cn=Manager,$base_DN -f basedomain.ldif 

firewall-cmd --add-service=ldap --permanent 
firewall-cmd --reload

cat > ldapuser.ldif <<-EOF
dn: uid=ldapuser,ou=People,$base_DN
objectClass: inetOrgPerson
objectClass: posixAccount
objectClass: shadowAccount
cn: Ldapuser
sn: Linux
userPassword: $password_hash
loginShell: /bin/bash
uidNumber: 1100
gidNumber: 1100
homeDirectory: /home/ldapuser

dn: cn=ldapuser,ou=Group,$base_DN
objectClass: posixGroup
cn: Ldapuser
gidNumber: 1100
memberUid: ldapuser
EOF

ldapadd -w $password -x -D cn=Manager,$base_DN -f ldapuser.ldif 

cd /etc/pki/tls/certs
umask 77 ; /usr/bin/openssl genrsa -aes128 -passout pass:$password 2048 > server.key
openssl rsa -passin pass:$password -in server.key -out server.key

umask 77 ; /usr/bin/openssl req -subj "/C=/ST=/L=/O=/CN=$fully_qualified_domain_name" -utf8 -new -key server.key -out server.csr
openssl x509 -in server.csr -out server.crt -req -signkey server.key -days 3650

cp /etc/pki/tls/certs/server.key \
/etc/pki/tls/certs/server.crt \
/etc/pki/tls/certs/ca-bundle.crt \
/etc/openldap/certs/ 

chown ldap. /etc/openldap/certs/server.key \
/etc/openldap/certs/server.crt \
/etc/openldap/certs/ca-bundle.crt

cat > mod_ssl.ldif <<-EOF
dn: cn=config
changetype: modify
add: olcTLSCACertificateFile
olcTLSCACertificateFile: /etc/openldap/certs/ca-bundle.crt
-
replace: olcTLSCertificateFile
olcTLSCertificateFile: /etc/openldap/certs/server.crt
-
replace: olcTLSCertificateKeyFile
olcTLSCertificateKeyFile: /etc/openldap/certs/server.key

EOF

ldapmodify -Y EXTERNAL -H ldapi:/// -f mod_ssl.ldif 

cp /etc/sysconfig/slapd /etc/sysconfig/slapd.installed
sed 's%SLAPD_URLS="ldapi:/// ldap:///"%SLAPD_URLS="ldapi:/// ldap:/// ldaps:///"%' /etc/sysconfig/slapd.installed > /etc/sysconfig/slapd

systemctl restart slapd 
systemctl start httpd 
cp /etc/openldap/certs/server.crt /var/www/html/
chmod 644 /var/www/html/server.crt



echo "Finished!"

echo -e "To connect to this ldap server, please run the following commands on a client:\n"
echo -e "yum -y install openldap-clients nss-pam-ldapd net-tools\nauthconfig --disableldap --disableldapauth --disableldaptls --update\nauthconfig --enableldap --enableldapauth --ldapserver=$fully_qualified_domain_name --ldapbasedn="$base_DN" --update"
echo 'echo "TLS_REQCERT allow" >> /etc/openldap/ldap.conf'
echo 'echo "tls_reqcert allow" >> /etc/nslcd.conf'
echo "authconfig --enableldaptls --ldaploadcacert=http://$fully_qualified_domain_name/server.crt --update"

