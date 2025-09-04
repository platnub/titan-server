# ‼️ Requirements for **EVERY** docker container
 1. Configuration script below
     - The only 2 exceptions are Pangolin host and Komodo host
 2. User account created
 3. A healthy mindset

---

# Host configuration script

‼️ Do not run if creating [Pangolin host](https://github.com/platnub/titan-server/blob/main/docker/containers/pangolin) or [Komodo host](https://github.com/platnub/container-host-templates/tree/main/docker/containers/komodo)

1. ```
   curl -fsSL https://github.com/platnub/titan-server/blob/main/docker/setup.sh
   ```
# Container user accounts

⚠️ Not all containers can run as an unpriveledged user

```
useradd -r <container-name>
id <conatiner-name>
```
