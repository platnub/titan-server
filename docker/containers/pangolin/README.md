[03-09-2025]
## Requirements
 - VM setup using Proxmox script
 - Komodo core server
 - Domain managed through Cloudflare

## Info
 - Installs and fully configures
   - Fail2ban
   - UFW
   - Docker
   - Komodo Periphery
   - Pangolin
   - Crowdsec
   - Geoblock
 - Sets up DigitalOcean VPS host SSH port
 - Creates users
 - Disables IPv6

⚠️ Incase anything goes wrong, example files are in the config folder.

‼️ Replace <ssh_port>

‼️ It will prompt you to set the "pangolin-service" (sudo) password when finished

1. ```
   # Install SSH and UFW
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
   sed -i 's|ExecStart=/opt/digitalocean/bin/droplet-agent |ExecStart=/opt/digitalocean/bin/droplet-agent -sshd_port=<ssh_port>|g' /etc/init/droplet-agent.conf
   
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
   passwd komodo
   ```

‼️ Set user "pangolin" password

   ```
   passwd pangolin
   ```

‼️ Login as user "komodo"

‼️ Replace <allowed_ips> with Komodo host public IP, or exclude that line

‼️ Replace <passkey> with Komodo host passkey

   ```
   # Download and create config file
   mkdir -p /home/komodo/.config/komodo && curl -o /home/komodo/.config/komodo/periphery.config.toml https://raw.githubusercontent.com/moghtech/komodo/refs/heads/main/config/periphery.config.toml

   # Modify config options of Periphery
   ## root_directory = "/home/komodo/periphery"
   sed -i 's|root_directory = "/etc/komodo"|root_directory = "/home/komodo/periphery"|g' /home/komodo/.config/komodo/periphery.config.toml
   ## allowed_ips = [1.2.3.0/24,1.2.3.4]
   sed -i 's|allowed_ips = \[\]|allowed_ips = \["<allowed_ips>"\]|g' /home/komodo/.config/komodo/periphery.config.toml
   ## stack_dir = "/opt/docker"
   sed -i 's|# stack_dir = "/etc/komodo/stacks"|stack_dir = "/opt/docker"|g' /home/komodo/.config/komodo/periphery.config.toml
   ## stats_polling_rate = "1-sec"
   sed -i 's|stats_polling_rate = "5-sec"|stats_polling_rate = "1-sec"|g' /home/komodo/.config/komodo/periphery.config.toml
   ## container_stats_polling_rate = "1-sec"
   sed -i 's|container_stats_polling_rate = "30-sec"|container_stats_polling_rate = "1-sec"|g' /home/komodo/.config/komodo/periphery.config.toml
   ## passkey = ["1234423h792387g4r"]
   sed -i 's|passkeys = \[\]|passkeys = ["<passkey>"]|g' /home/komodo/.config/komodo/periphery.config.toml

   # Install Periphery
   curl -sSL https://raw.githubusercontent.com/moghtech/komodo/main/scripts/setup-periphery.py | python3 - --user
   ```
   
   ```
   loginctl enable-linger $USER
   systemctl --user enable periphery
   systemctl --user status periphery
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

   ```
   docker compose down
   rm -rf installer && rm -rf config.tar.gz
   mkdir appdata
   mv config appdata
   chown -R komodo:komodo /opt/docker/pangolin-core
   ```

3. Create pangolin-core stack in Komodo using [compose.yml](https://github.com/platnub/titan-server/blob/main/docker/containers/pangolin/compose.yml)
4. Deploy the stack and check if it starts without issues
5. Destroy the stack in Komodo

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

ℹ️ Continue using instructions from [HHF Technology Forum](https://forum.hhf.technology/t/crowdsec-manager-for-pangolin-user-guide/579)

‼️ Use the following options when the script starts
 - [Recommended] Option 10: Enroll with CrowdSec console (Login in to the [CrowdSec console](https://app.crowdsec.net/) and get the string from the "Connect with console" command at the bottom
 - [Recommended] Option 11: Set up custom scenarios
 - [Recommended] Option 12: Set up captcha protections (Get an API key from [Cloudflare Turnstile](https://dash.cloudflare.com/). Make it "Non-interactive")

10. ```
    cd /opt/docker/pangolin-core/appdata
    curl -o setup_crowdsec_manager.sh https://gist.githubusercontent.com/hhftechnology/aadadf48ac906fc38cfd0d7088980475/raw/0a384d518e74c9963a51fcfb60d5ef5bccf9f645/setup_crowdsec_manager.sh
    chmod +x setup_crowdsec_manager.sh
    ./setup_crowdsec_manager.sh
    ```
    
11. Deploy the stack and check if it starts without issues
12. Destroy the stack

ℹ️ Continue using instructions from [HHF Technology Forum](https://forum.hhf.technology/t/implementing-geoblocking-in-pangolin-stack-with-traefik/490)

⚠️ Optionally check for new version [releases](https://github.com/david-garcia-garcia/traefik-geoblock/releases)

13. ```
    cd /home/docker/pangolin-core/appdata/config/traefik
    
    awk '/^      middlewares:$/ {print; print "        - pangolin-geoblock@file"; next} 1' traefik_config.yml > tmp && mv tmp traefik_config.yml
    awk '/^  plugins:$/ {print; print "    geoblock:"; print "      moduleName: github.com/david-garcia-garcia/traefik-geoblock"; print "      version: v1.1.1"; next} 1' traefik_config.yml > tmp && mv tmp traefik_config.yml
    
    awk '/^  plugins:$/ {
      print;
      print "    pangolin-geoblock:";
      print "      plugin:";
      print "        geoblock:";
      print "          enabled: true";
      print "          defaultAllow: false";
      print "          databaseFilePath: \"/plugins-storage/IP2LOCATION-LITE-DB1.IPV6.BIN\"";
      print "          allowPrivate: true";
      print "          logBannedRequests: true";
      print "          banIfError: true";
      print "          disallowedStatusCode: 403";
      print "          allowedCountries:";
      print "            - AL # Albania";
      print "          allowedIPBlocks:";
      print "            - 192.168.0.0/16";
      print "            - 10.0.0.0/8";
      print "          bypassHeaders:";
      print "            X-Internal-Request: true";
      print "            X-Skip-Geoblock: 1";
      next
    } 1' dynamic_config.yml > tmp && mv tmp dynamic_config.yml


    ```

‼️ Decide which allowedCountries you want to add from [this list](https://github.com/platnub/titan-server/blob/main/docker/containers/pangolin/geoblock_country_list.yml) or find more [here](https://en.wikipedia.org/wiki/ISO_3166-1_alpha-2#Officially_assigned_code_elements)

    ```
    nano /opt/docker/pangolin-core/appdata/config/traefik/dynamic_config.yml
    ...

14. Uncomment the following line in the compose.yml file (through Komodo)

    ```
     - ./IP2LOCATION-LITE-DB1.IPV6.BIN:/plugins-storage/IP2LOCATION-LITE-DB1.IPV6.BIN
    ```

15. ```
    cd /opt/docker/pangolin-core/appdata
    wget https://github.com/david-garcia-garcia/traefik-geoblock/raw/refs/heads/master/IP2LOCATION-LITE-DB1.IPV6.BIN
    ```
