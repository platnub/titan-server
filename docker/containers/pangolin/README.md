[03-09-2025]
## Requirements
 - VM setup using Proxmox script
 - Domain managed through Cloudflare
 - Pangolin VPS setup using script

ℹ️ Start Pangolin install using instructions from [Pangolin](https://docs.digpangolin.com/self-host/quick-install)

‼️ Follow installer instructions
 - [Optional] Email setup
 - [Highly Recommended] CrowdSec installation

1. ```
   mkdir /opt/docker/pangolin-core && cd/opt/docker/pangolin-core
   curl -fsSL https://digpangolin.com/get-installer.sh | bash
   sudo ./installer
   ```

2. ```
   docker compose down
   rm -rf installer && rm -rf config.tar.gz
   mkdir appdata
   mv config appdata
   chown -R komodo:komodo /opt/docker/pangolin-core
   ```

3. Create pangolin-core stack in Komodo using [compose.yml](https://github.com/platnub/titan-server/blob/main/docker/containers/pangolin/compose.yml)
4. Deploy the stack and check if it starts without issues
5. Destroy the stack

ℹ️ Configure wildcard certificates using instructions from [Pangolin]()

‼️ Make sure to replace example.com

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
 - [Recommended] Option 12: Set up captcha protections (Get an API key from [Cloudflare Turnstile](https://dash.cloudflare.com/). Make it "non-interactive")

10. ```
    curl -o setup_crowdsec_manager.sh https://gist.githubusercontent.com/hhftechnology/aadadf48ac906fc38cfd0d7088980475/raw/0a384d518e74c9963a51fcfb60d5ef5bccf9f645/setup_crowdsec_manager.sh
    chmod +x setup_crowdsec_manager.sh
    ./setup_crowdsec_manager.sh
    ```
    
12. Destroy the stack
