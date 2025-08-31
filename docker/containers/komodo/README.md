# Requirements
1. Socket proxy

# .env variables to configure
1. KOMODO_PASSKEY

# appdata folders to create
1. mongo-data
2. mongo-config
3. backups

# Installation steps
1. Create user with home folder for komodo periphery

# Installation steps script
```
useradd --create-home komodo
usermod -aG docker komodo
passwd -l komodo
```
