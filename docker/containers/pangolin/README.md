[03-09-2025]
## Requirements
 - VM setup using Proxmox script
 - Domain managed through Cloudflare

⚠️ Incase anything goes wrong, example files are in the config folder.

‼️ Replace <ssh_port>

‼️ It will prompt you to set the "pangolin-service" (sudo) password when finished

1. ```
   # Install everything
   apt-get update -y && apt-get upgrade -y
   apt-get install ssh -y
   apt-get install fail2ban -y
   apt-get install ufw -y
   
   # Configure users
   useradd -r pangolin-service
   usermod -aG sudo pangolin-service
   passwd -l root
   useradd -r pangolin
   useradd --create-home komodo
   usermod -aG docker komodo

   # Change SSH port, disable IPv6, Setup UFW firewall
   sed -i 's/\#Port 22/Port <ssh_port> /' /etc/ssh/sshd_config

   # Optional DigitalOcean VPS host SSH port step
   # sed -i 's|ExecStart=/opt/digitalocean/bin/droplet-agent |ExecStart=/opt/digitalocean/bin/droplet-agent -sshd_port=<ssh_port>|g' /etc/init/droplet-agent.conf
   
   systemctl daemon-reload
   systemctl restart sshd
   echo -e "\n# Disabling the IPv6\nnet.ipv6.conf.all.disable_ipv6 = 1\nnet.ipv6.conf.default.disable_ipv6 = 1\nnet.ipv6.conf.lo.disable_ipv6 = 1" | sudo tee -a /etc/sysctl.conf > /dev/null
   sysctl -p
   sed -i 's|IPV6=yes|IPV6=no|g' /etc/default/ufw
   ufw default deny incoming
   ufw default allow outgoing
   ufw allow <ssh_port>
   ufw allow 80/tcp
   ufw allow 443/tcp
   ufw allow 51820/udp
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
   passwd pangolin-service
   ```

‼️ Set user "komodo" password

   ```
   passwd pangolin
   ```

‼️ Set user "pangolin" password

   ```
   passwd pangolin
   ```

ℹ️ Start the Pangolin install using instructions from [Pangolin](https://docs.digpangolin.com/self-host/quick-install)

‼️ Follow installer instructions
 - [Optional] Email setup
 - [Highly Recommended] CrowdSec installation

2. ```
   mkdir /opt/docker/pangolin-core && cd/opt/docker/pangolin-core
   curl -fsSL https://digpangolin.com/get-installer.sh | bash
   sudo ./installer
   ```

3. ```
   docker compose down
   rm -rf installer && rm -rf config.tar.gz
   mkdir appdata
   mv config appdata
   chown -R komodo:komodo /opt/docker/pangolin-core
   ```

4. Create pangolin-core stack in Komodo using [compose.yml](https://github.com/platnub/titan-server/blob/main/docker/containers/pangolin/compose.yml)
5. Deploy the stack and check if it starts without issues
6. Destroy the stack in Komodo

ℹ️ Configure wildcard certificates using instructions from [Pangolin]()

‼️ Replace example.com

6. ```
   cd /opt/docker/pangolin-core/appdata/config
   awk '/^        cert_resolver: "letsencrypt"$/ {print; print "        prefer_wildcard_cert: true"; next} 1' config.yml > tmp && mv tmp config.yml
   cd traefik
   sed -i 's/^      httpChallenge:$/      dnsChallenge:/' traefik_config.yml
   sed -i 's/^        entryPoint: web$/        provider: "cloudflare"/' traefik_config.yml
   awk '
   /^      service: next-service$/ {
       service_line = $0;
       getline;  # Read next line
       tls_line = $0;
       getline;  # Read next line
       cert_line = $0;
       if (tls_line ~ /^      tls:$/ && cert_line ~ /^        certResolver: letsencrypt$/) {
           print service_line;
           print tls_line;
           print cert_line;
           print "        domains:";
           print "          - main: \"example.com\"";
           print "            sans:";
           print "              - \"*.example.com\"";
       next
       }
       print service_line;
       print tls_line;
       print cert_line;
       next;
   }
   1' dynamic_config.yml > tmp && mv tmp dynamic_config.yml
   ```

7. Uncomment the following 2 lines in the compose.yml file (through Komodo) and fill in your Cloudflare API key.

   **Cloudflare API key requirements:**
    - Zone/Zone/Read
    - Zone/DNS/Edit
    - Apply to all zones

   ```
     environment:
       CLOUDFLARE_DNS_API_TOKEN: "your-cloudflare-api-token"
   ```

8. Deploy the stack and check if it starts without issues
9. Destroy the stack

ℹ️ Continue using instructions from [ - HHF Technology Forum](https://forum.hhf.technology/t/crowdsec-manager-for-pangolin-user-guide/579)

‼️ Use the following options when the script starts
 - [Recommended] Option 10: Enroll with CrowdSec console (Login in to the [CrowdSec console](https://app.crowdsec.net/) and get the string from the "Connect with console" command at the bottom
 - [Recommended] Option 11: Set up custom scenarios
 - [Recommended] Option 12: Set up captcha protections (Get an API key from [Cloudflare Turnstile](https://dash.cloudflare.com/). Make it "Non-interactive")

10. ```
    curl -o setup_crowdsec_manager.sh https://gist.githubusercontent.com/hhftechnology/aadadf48ac906fc38cfd0d7088980475/raw/0a384d518e74c9963a51fcfb60d5ef5bccf9f645/setup_crowdsec_manager.sh
    chmod +x setup_crowdsec_manager.sh
    ./setup_crowdsec_manager.sh
    ```
    
12. Destroy the stack in Komodo
13. 
