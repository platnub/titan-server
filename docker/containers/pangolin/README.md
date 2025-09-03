[03-09-2025]
## Requirements
 - VM setup using Proxmox script
 - Pangolin VPS setup using script

ℹ️ Start install using instructions from [Pangolin](https://docs.digpangolin.com/self-host/quick-install)
1. ```
   mkdir /opt/docker/pangolin-core && cd/opt/docker/pangolin-core
   curl -fsSL https://digpangolin.com/get-installer.sh | bash
   sudo ./installer
   ```
‼️ Follow installer instructions
 - [Optional] Email setup
 - [Highly Recommended] CrowdSec installation
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
Configure wildcard certificates using instructions from [Pangolin]()
6. ```
   awk '/^        cert_resolver: "letsencrypt"$/ {print; print "        prefer_wildcard_cert: true"; next} 1' config.yml > tmp && mv tmp config.yml
   
   ```
ℹ️ Continue using instructions from [ - HHF Technology Forum](https://forum.hhf.technology/t/crowdsec-manager-for-pangolin-user-guide/579)
7. 
