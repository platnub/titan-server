# Requirements
1. Proxmox processor type = host
2. Socket proxy

# Installation steps

‼️ It will prompt you to set the "komodo-service" user password when finished

1. ```
   # Install SSH and UFW
   apt-get update -y && apt-get upgrade -y
   apt-get install ssh -y
   apt-get install fail2ban -y
   apt-get install ufw -y
   
   # Change SSH port, disable IPv6, Setup UFW firewall
   sed -i 's/\#Port 22/Port <ssh_port> /' /etc/ssh/sshd_config
   
   systemctl daemon-reload
   systemctl restart sshd
   echo -e "\n# Disabling the IPv6\nnet.ipv6.conf.all.disable_ipv6 = 1\nnet.ipv6.conf.default.disable_ipv6 = 1\nnet.ipv6.conf.lo.disable_ipv6 = 1" | sudo tee -a /etc/sysctl.conf > /dev/null
   sysctl -p
   sed -i 's|IPV6=yes|IPV6=no|g' /etc/default/ufw
   ufw default deny incoming
   ufw default allow outgoing
   ufw allow <ssh_port>
   ufw allow 9120/tcp
   ufw --force enable
   
   # Install and configure Docker
   apt-get install ca-certificates curl
   install -m 0755 -d /etc/apt/keyrings
   curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
   chmod a+r /etc/apt/keyrings/docker.asc
   echo \
   "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian \
   $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
   tee /etc/apt/sources.list.d/docker.list > /dev/null
   apt update -y
   apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin -y
   
   # Create user and folders
   useradd --create-home komodo-service
   mkdir /opt/docker
   chown komodo-service:komodo-service /opt/docker
   chmod 700 /opt/docker
   usermod -aG docker komodo-service
   passwd komodo-service
   ```
2. Create komodo container
   ```
   mkdir /opt/docker/komodo
   wget https://github.com/platnub/container-host-templates/blob/main/docker/containers/komodo/.env
   wget https://github.com/platnub/container-host-templates/blob/main/docker/containers/komodo/compose.yml
   ```
3. Edit .env file
       - Use `openssl rand -hex 64` for PASSKEY and JWT
      1. KOMODO_PASSKEY
      2. KOMODO_HOST
      3. KOMODO_JWT_SECRET
  
4. 
