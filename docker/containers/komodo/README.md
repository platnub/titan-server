# Requirements
1. Socket proxy

# .env variables to configure
1. KOMODO_PASSKEY
2. KOMODO_HOST
3. KOMODO_WEBHOOK_SECRET
4. KOMODO_JWT_SECRET

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
