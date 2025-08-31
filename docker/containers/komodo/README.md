# Requirements
1. Socket proxy

# .env variables to configure
1. KOMODO_PASSKEY
2. /home instead of /etc.....!!!

# appdata folders to create
1. mongo-data
2. mongo-config

# Installation steps
1. Create user with home folder for komodo periphery
2. Create backup directory

# Installation steps script
```
useradd --create-home komodo
usermod -aG docker komodo
passwd -l komodo
```
