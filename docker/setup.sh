# Install SSH and UFW
apt-get update -y && apt-get upgrade -y
apt-get install ssh -y
apt-get install fail2ban -y
apt-get install ufw -y

# Configure users
useradd --create-home komodo

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
ufw allow 8120/tcp
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

# Create folders
mkdir /opt/docker
chown komodo:komodo /opt/docker
chmod 700 /opt/docker
usermod -aG docker komodo
passwd komodo

# Download and create config file
mkdir -p /home/komodo/.config/komodo && cd /home/komodo/.config/komodo && curl -o ./periphery.config.toml https://raw.githubusercontent.com/moghtech/komodo/refs/heads/main/config/periphery.config.toml
# Modify config options of Periphery
## root_directory = "/home/komodo/periphery"
sed -i 's|root_directory = "/etc/komodo"|root_directory = "/home/komodo/periphery"|g' ./periphery.config.toml
## allowed_ips = [1.2.3.0/24,1.2.3.4]
sed -i 's|allowed_ips = \[\]|allowed_ips = \["<allowed_ips>"\]|g' ./periphery.config.toml
## stack_dir = "/opt/docker"
sed -i 's|# stack_dir = "/etc/komodo/stacks"|stack_dir = "/opt/docker"|g' ./periphery.config.toml
## stats_polling_rate = "1-sec"
sed -i 's|stats_polling_rate = "5-sec"|stats_polling_rate = "1-sec"|g' ./periphery.config.toml
## container_stats_polling_rate = "1-sec"
sed -i 's|container_stats_polling_rate = "30-sec"|container_stats_polling_rate = "1-sec"|g' ./periphery.config.toml
# Install Periphery
cd /home/komodo
curl -sSL https://raw.githubusercontent.com/moghtech/komodo/main/scripts/setup-periphery.py | python3 - --user
loginctl enable-linger $USER
systemctl --user enable periphery
systemctl --user status periphery
