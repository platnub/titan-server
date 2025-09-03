[03-09-2025]
## Requirements
- VM setup using Proxmox script
- Pangolin VPS setup using script
```diff
# Start install using instructions from: https://docs.digpangolin.com/self-host/quick-install
```
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
4. Create `pangolin-core` stack in Komodo
5. 
