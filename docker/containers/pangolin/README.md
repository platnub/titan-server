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
2. Follow installer instructions
   - [Optional] Email setup
   - [Highly Recommended] CrowdSec installation
3. ```
   docker compose down
   rm -rf installer && rm -rf config.tar.gz
   mkdir appdata
   mv config appdata
   chown -R komodo:komodo /opt/docker/pangolin-core
   ```
4. Create `pangolin-core` stack in Komodo using [compose.yml](https://github.com/platnub/titan-server/blob/main/docker/containers/pangolin/compose.yml)
5. Deploy the stack and check if it starts without issues
6. Destroy the stack
Configure wildcard certificates using instructions from [Pangolin]()
7. ```
   sed -i '/^        cert_resolver: "letsencrypt"$/        prefer_wildcard_cert: true\n' config.yml
   ```
ℹ️ Continue using instructions from [ - HHF Technology Forum](https://forum.hhf.technology/t/crowdsec-manager-for-pangolin-user-guide/579)
8. 
