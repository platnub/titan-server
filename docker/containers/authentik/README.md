1. ```
   useradd -r authentik
   id authentik
   ```
2. Create stack in Komodo using [compose.yml](https://github.com/platnub/titan-server/blob/main/docker/containers/authentik/compose.yml) and [.env](https://github.com/platnub/titan-server/blob/main/docker/containers/authentik/.env)
3. Deploy the stack and then stop it
4. Use these commands to generate 2 secrets
```
cd /opt/docker/authentik
echo "PG_PASS=$(openssl rand -base64 36 | tr -d '\n')" >> .env
echo "AUTHENTIK_SECRET_KEY=$(openssl rand -base64 60 | tr -d '\n')" >> .env
```
5. Deploy the stack and go to authentik.example.comif/flow/initial-setup/
