1. Create stack in Komodo using [compose.yml](https://github.com/platnub/titan-server/blob/main/docker/containers/authentik/compose.yml) and [.env](https://github.com/platnub/titan-server/blob/main/docker/containers/authentik/.env)
2. Use these commands to generate 2 secrets and paste them into the .env
```
"PG_PASS=$(openssl rand -base64 36 | tr -d '\n')"
"AUTHENTIK_SECRET_KEY=$(openssl rand -base64 60 | tr -d '\n')"
```
3. Fill in the rest of the .env variables
4. Deploy the stack and go to authentik.example.com/if/flow/initial-setup/
