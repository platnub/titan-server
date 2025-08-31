# Requirements
1. Proxmox processor type = host
2. Socket proxy

# .env variables to configure - Use `openssl rand -hex 32` for PASSKEY and JWT
1. KOMODO_PASSKEY
2. KOMODO_HOST
3. KOMODO_JWT_SECRET

# Installation steps
1. Create user **with** home folder for komodo periphery
2. Create docker container folders and compose container

# Useful commands
```
useradd --create-home komodo
usermod -aG docker komodo
passwd -l komodo
```
