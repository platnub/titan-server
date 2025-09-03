1. Create stack in Komodo using [compose.yml](https://github.com/platnub/titan-server/blob/main/docker/containers/authentik/compose.yml) and [.env](https://github.com/platnub/titan-server/blob/main/docker/containers/authentik/.env)
2. Deploy the stacka and then top it
3. Use these commands to generate 2 secrets
```
cd /opt/docker/authentik
echo "PG_PASS=$(openssl rand -base64 36 | tr -d '\n')" >> .env
echo "AUTHENTIK_SECRET_KEY=$(openssl rand -base64 60 | tr -d '\n')" >> .env
```
