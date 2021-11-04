
Установка Stunnel - OpenVPN - на CentOS 8
``` 
cd ~
wget https://raw.githubusercontent.com/fogiznt/Stunnel-OVPN-CentOS8/main/stunnel-openvpn-install.sh --secure-protocol=TLSv1
chmod +x stunnel-openvpn-install.sh
./stunnel-openvpn-install.sh
```

Импорт сертификатов в домашнюю директорию - C:\Users\User\
``` 
scp root@server_ip:"/tmp/{eakj-*,stunnel-server.crt,client.ovpn}" .
``` 

