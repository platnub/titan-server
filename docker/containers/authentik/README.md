# Info
 - Pangolin connection: https://authentik:9443
   - Leave unprotected

# Instructions
1. Create stack in Komodo using [compose.yml](https://github.com/platnub/titan-server/blob/main/docker/containers/authentik/compose.yml) and [.env](https://github.com/platnub/titan-server/blob/main/docker/containers/authentik/.env)
2. Use these commands to generate 2 secrets and paste them into the .env
```
"PG_PASS=$(openssl rand -base64 36 | tr -d '\n')"
"AUTHENTIK_SECRET_KEY=$(openssl rand -base64 60 | tr -d '\n')"
```
3. Fill in the rest of the .env variables
   - Fill in reverse proxy CIDN if needed `AUTHENTIK_LISTEN__TRUSTED_PROXY_CIDRS`
4. Deploy the stack and go to authentik.example.com/if/flow/initial-setup/

# Extra guides
## Cloudflare Turnstile Captchas _[source](https://www.youtube.com/watch?v=Fe5SttNa2lU)_
1. Create Turnstile widget on [Cloudflare](https://dash.cloudflare.com/)
2. Create new Stage in Authentik
  1. Captcha Stage
  2. Name `cloudflare-turnstile`
  3. Public and Private key from Turnstile widget created in step 1
  4. Interactive: Enabled
  5. Advanced settings:
     - JS URL: https://challenges.cloudflare.com/turnstile/v0/api.js
     - API URL: https://challenges.cloudflare.com/turnstile/v0/siteverify
3. Select main authentication Flow in Authentik (default-authentication-flow)
  1. Select Stage Binding
  2. Bind existing stage
  3. Select Captcha stage `cloudflare-turnstile`
  4. Order 15
