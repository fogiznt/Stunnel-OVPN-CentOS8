#!/bin/bash
yum install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm
yum update -y
echo -e "SELINUX=permissive\nSELINUXTYPE=targeted" > /etc/selinux/config
yum install -y iptables-services openvpn unzip
cd /opt/ && curl -O -L https://github.com/OpenVPN/easy-rsa/archive/master.zip
unzip master.zip && rm -f master.zip
cd easy-rsa-master/easyrsa3/ && cp vars.example vars
echo -e "set_var EASYRSA_DN     "cn_only"\nset_var EASYRSA_ALGO            ec\nset_var EASYRSA_CURVE           secp521r1\nset_var EASYRSA_CA_EXPIRE       3650\nset_var EASYRSA_CERT_EXPIRE     3650\nset_var EASYRSA_CRL_DAYS        3650" > /opt/easy-rsa-master/easyrsa3/vars
export EASYRSA_VARS_FILE=/opt/easy-rsa-master/easyrsa3/vars
./easyrsa init-pki
./easyrsa --batch build-ca nopass
./easyrsa build-server-full openvpn-server nopass
./easyrsa build-client-full openvpn-client nopass
cp -p pki/ca.crt pki/private/openvpn-server.key pki/issued/openvpn-server.crt /etc/openvpn/server/
cp -p pki/ca.crt pki/private/openvpn-client.key pki/issued/openvpn-client.crt /tmp/
cd /etc/openvpn/server/
openvpn --genkey --secret ta.key
cp -p ta.key /tmp/
ip=$(curl check-host.net/ip 2>/dev/null) >&- 2>&-
cat >>/etc/openvpn/server/openvpn-server.conf<<EOF
### Bind на loopback-адрес и стандартный порт,
### так как коннект из интернета все равно получает stunnel
local 127.0.0.1
port 1194
proto tcp
dev tun

ca ca.crt
cert openvpn-server.crt
key openvpn-server.key
dh none
tls-auth ta.key 0
tls-cipher TLS-ECDHE-ECDSA-WITH-AES-256-GCM-SHA384:TLS-ECDHE-ECDSA-WITH-CHACHA20-POLY1305-SHA256
cipher AES-256-GCM

server 10.8.8.0 255.255.255.0
push "redirect-gateway def1"
push "route $ip 255.255.255.255 net_gateway"
push "dhcp-option DNS 1.1.1.1"
push "dhcp-option DNS 1.1.1.1"

duplicate-cn
keepalive 10 120

user nobody
group nobody
persist-key
persist-tun

status /dev/null
log /dev/null
verb 0
EOF
systemctl start openvpn-server@openvpn-server
systemctl enable openvpn-server@openvpn-server
wget https://download-ib01.fedoraproject.org/pub/epel/8/Everything/x86_64/Packages/t/tcp_wrappers-libs-7.6-96.el8.x86_64.rpm
rpm -Uvh tcp_wrappers-libs-7.6-96.el8.x86_64.rpm
dnf install tcp_wrappers-libs
cd /opt && curl -O -L https://cbs.centos.org/kojifiles/packages/stunnel/5.41/1.el7/x86_64/stunnel-5.41-1.el7.x86_64.rpm
rpm -ivh stunnel-5.41-1.el7.x86_64.rpm
useradd -d /var/stunnel -m -s /bin/false stunnel
mkdir /etc/stunnel
touch /etc/stunnel/stunnel.conf
cat >>/etc/stunnel/stunnel.conf<<EOF
### Помни: exec исполняется из каталога chroot!
chroot = /var/stunnel
setuid = stunnel
setgid = stunnel
pid = /stunnel.pid

debug = 0

## performance tunning
socket = l:TCP_NODELAY=1
socket = r:TCP_NODELAY=1

### curve used for ECDHE
curve = secp521r1
sslVersion = all
options = NO_SSLv2
options = NO_SSLv3

[openvpn]
accept = 443
connect = 127.0.0.1:1194
renegotiation = no

### RSA
ciphers = ECDHE-RSA-AES256-GCM-SHA384:ECDHE-RSA-CHACHA20-POLY1305:ECDHE-RSA-AES256-SHA
cert = /etc/stunnel/stunnel-server.crt
key = /etc/stunnel/stunnel-server.key
CAfile = /etc/stunnel/clients.crt
verifyPeer = yes
EOF
cd /etc/stunnel
openssl req -newkey rsa:2048 -nodes -keyout stunnel-server.key -x509 -days 3650 -subj "/CN=stunnel-server" -out stunnel-server.crt
openssl req -newkey rsa:2048 -nodes -keyout eakj-desktop.key   -x509 -days 3650 -subj "/CN=eakj-desktop"   -out eakj-desktop.crt
openssl req -newkey rsa:2048 -nodes -keyout eakj-mobile.key   -x509 -days 3650 -subj "/CN=eakj-mobile"   -out eakj-mobile.crt
openssl pkcs12 -export -in eakj-mobile.crt   -inkey eakj-mobile.key -out eakj-mobile.p12
cat eakj-desktop.crt > /etc/stunnel/clients.crt
cat eakj-mobile.crt >> /etc/stunnel/clients.crt
systemctl start stunnel
systemctl enable stunnel
cp -p eakj-* stunnel-server.crt /tmp/
systemctl enable iptables
systemctl stop firewalld
systemctl disable firewalld
iptables -A FORWARD -i tun+ -s 10.8.8.0/24 -j ACCEPT
iptables -t nat -A POSTROUTING -s 10.8.8.0/24 -j MASQUERADE
service iptables save
systemctl enable iptables
echo 1 >/proc/sys/net/ipv4/ip_forward
echo net.ipv4.ip_forward = 1 >>/etc/sysctl.conf
cd /tmp/
ca=$(cat /tmp/ca.crt )
cert=$(cat /tmp/openvpn-client.crt)
key=$(cat /tmp/openvpn-client.key)
tls=$(cat /tmp/ta.key)
ip=$(curl check-host.net/ip)
cat >client.ovpn <<EOF
client
dev tun
proto tcp
remote 127.0.0.1 1194
resolv-retry infinite
nobind
user nobody
group nobody
persist-key
persist-tun

remote-cert-tls server
cipher AES-256-GCM
<ca>
$ca
</ca>
<cert>
$cert
</cert>
<key>
$key
</key>
key-direction 1
<tls-auth>
$tls
</tls-auth>
EOF
