# ldap-tls-gce
set up an ldap-tls server on google compute engine

The Lightweight Directory Access Protocol, or LDAP, is an open, vendor-neutral, industry standard application protocol for accessing and maintaining distributed directory information services over an Internet Protocol (IP) network.

key concepts and terms:
1. A LDAP directory is a tree of data entries that is hierarchical in nature and is called the Directory Information Tree (DIT).
2. An entry consists of a set of attributes.
3. An attribute has a type (a name/description) and one or more values.
4. Every attribute must be defined in at least one objectClass.
5. Attributes and objectclasses are defined in schemas (an objectclass is actually considered as a special kind of attribute).
6. Each entry has a unique identifier: its Distinguished Name (DN or dn). This, in turn, consists of a Relative Distinguished Name (RDN) followed by the parent entry's DN.
7. The entry's DN is not an attribute. It is not considered part of the entry itself.


USAGE:

PASSWORD="PUT_YOUR_PASSWORD_HERE" ./setup-ldap.sh
