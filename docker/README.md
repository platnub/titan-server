# ‼️ Requirements for **EVERY** docker container
 1. Configuration script below
     - The only 2 exceptions are Pangolin host and Komodo host
 2. User account created
 3. A healthy mindset

---

# Host configuration script

‼️ Do not run if creating [Pangolin host](https://github.com/platnub/titan-server/blob/main/docker/containers/pangolin) or [Komodo host](https://github.com/platnub/container-host-templates/tree/main/docker/containers/komodo)

1. Connect to the VM through SSH port 22 using sudo user
2.  ```
    sudo su
    ```
    ```
    sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/platnub/container-host-templates/refs/heads/main/docker/setup.sh)"
    ```
3. Connect to the VM through SSH using the komodo user
    ```
    # Install Periphery
    cd /home/komodo
    curl -sSL https://raw.githubusercontent.com/moghtech/komodo/main/scripts/setup-periphery.py | python3 - --user
    loginctl enable-linger $USER
    systemctl --user enable periphery
    systemctl --user status periphery
    ```

# Container user accounts

⚠️ Not all containers can run as an unpriveledged user

```
useradd -r <container-name>
passwd -l <container-name>
id <conatiner-name>
```
