# Default Settings
- SSH port 22
- Sudo user - Hostname is username

1. Run this from Proxmox node shell
    ```
    bash -c "$(curl -fsSL https://raw.githubusercontent.com/platnub/titan-server/refs/heads/main/virtual-machines/docker.sh)"
    ```
2. Connect to the VM through SSH port 22 using sudo user
3.  ```
    sudo su
    bash -c "$(curl -fsSL https://raw.githubusercontent.com/platnub/container-host-templates/refs/heads/main/docker/setup.sh)"
    ```
4. Connect to the VM through SSH using the komodo user
    ```
    # Install Periphery
    cd /home/komodo
    curl -sSL https://raw.githubusercontent.com/moghtech/komodo/main/scripts/setup-periphery.py | python3 - --user
    loginctl enable-linger $USER
    systemctl --user enable periphery
    systemctl --user status periphery
    ```
