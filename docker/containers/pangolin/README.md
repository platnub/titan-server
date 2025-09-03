[03-09-2025]
## Requirements
- VM setup using Proxmox script
- Pangolin VPS setup using script

$${\color{lightblue}Start install using instructions from: https://docs.digpangolin.com/self-host/quick-install}$$
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
   ```
4. Create `pangolin-core` stack in Komodo using [compose.yml](https://github.com/platnub/titan-server/blob/main/docker/containers/pangolin/compose.yml)
