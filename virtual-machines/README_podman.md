# ⛔ **Deprecated!!**

Create a Podman VM using:

_Advanced configuration is highly recommended_
```shell
bash -c "$(curl -fsSL https://raw.githubusercontent.com/platnub/titan-server/refs/heads/main/virtual-machines/podman.sh)"
```

* Creates a VM
* Installs Ubuntu
* Set Hostname
* Enable and configure firewall
* Creates user Podman with sudo password set during advanced setup (default: changeme)
* Locks default root user
* Installs Podman
* Installs Podman-compose
* Make Podman containers rootless
* Copy Podman registries.conf into Podman user home
* Add docker.io to registries.conf
* Enable Podman linger
* Installs SSH
* Installs Fail2ban
* Sets SSH port

# Extra Tweaks
## Servers with large amounts of files (Cloud storage, Media servers, etc.)
```
sudo /bin/su -c \"echo -e 'vm.swappiness=10\nvm.vfs_cache_pressure = 50\nfs.inotify.max_user_watches=262144' >> /etc/sysctl.conf"
```
