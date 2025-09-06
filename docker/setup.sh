#!/bin/bash

sudo su
# Install SSH and UFW
echo "Updating system packages..."
apt-get update -y && apt-get upgrade -y

echo "Installing SSH, Fail2Ban, and UFW..."
apt-get install ssh -y
apt-get install fail2ban -y
apt-get install ufw -y

# Configure users
echo "Creating komodo user..."
useradd --create-home komodo

# Get SSH port from user
read -p "Enter the SSH port you want to use (default: 22): " ssh_port
ssh_port=${ssh_port:-22}

# Change SSH port, disable IPv6, Setup UFW firewall
echo "Configuring SSH and firewall..."
sed -i "s/\#Port 22/Port $ssh_port/" /etc/ssh/sshd_config
systemctl daemon-reload
systemctl restart sshd

echo -e "\n# Disabling the IPv6\nnet.ipv6.conf.all.disable_ipv6 = 1\nnet.ipv6.conf.default.disable_ipv6 = 1\nnet.ipv6.conf.lo.disable_ipv6 = 1" | sudo tee -a /etc/sysctl.conf > /dev/null
sysctl -p
sed -i 's|IPV6=yes|IPV6=no|g' /etc/default/ufw

ufw default deny incoming
ufw default allow outgoing
ufw allow $ssh_port/tcp
ufw allow 8120/tcp
ufw --force enable

# Install and configure Docker
echo "Installing Docker..."
apt-get install ca-certificates curl -y
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
echo "Setting up directories..."
mkdir /opt/docker
chown komodo:komodo /opt/docker
chmod 700 /opt/docker
usermod -aG docker komodo

# Set komodo password
echo "-----------------------------------------------------------------------------"
echo "Setting password for komodo user..."
echo "You will now be prompted to set a password for the komodo user."
echo "Please choose a strong password and remember it as you'll need it to log in."
echo "-----------------------------------------------------------------------------"
passwd komodo

# Get allowed IPs from user
read -p "Enter allowed IP addresses (comma-separated, e.g., 1.2.3.0/24,1.2.3.4): " allowed_ips

# Get passkey from user
read -p "Enter the passkey (should be a secure random string): " passkey

# Download and create config file
echo "Configuring Komodo..."
mkdir -p /home/komodo/.config/komodo && cd /home/komodo/.config/komodo
curl -o ./periphery.config.toml https://raw.githubusercontent.com/moghtech/komodo/refs/heads/main/config/periphery.config.toml

# Modify config options of Periphery
sed -i 's|root_directory = "/etc/komodo"|root_directory = "/home/komodo/periphery"|g' ./periphery.config.toml
sed -i "s|allowed_ips = \[\]|allowed_ips = [$allowed_ips]|g" ./periphery.config.toml
sed -i 's|# stack_dir = "/etc/komodo/stacks"|stack_dir = "/opt/docker"|g' ./periphery.config.toml
sed -i 's|stats_polling_rate = "5-sec"|stats_polling_rate = "1-sec"|g' ./periphery.config.toml
sed -i 's|container_stats_polling_rate = "30-sec"|container_stats_polling_rate = "1-sec"|g' ./periphery.config.toml
sed -i "s|passkeys = \[\]|passkeys = [\"$passkey\"]|g" ./periphery.config.toml

chown -R komodo:komodo /home/komodo

echo "Configuration complete!"
echo "You can now SSH into this server using port $ssh_port and the komodo user."
