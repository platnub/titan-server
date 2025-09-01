# Instructions
1. Replace "domain.my" with domain using text edit in the script below
2. Replace "mail@domain.my" with email
3. Fill the pangolin user and group ID's into `.env`
4. Run script "Pre Deploy" using Komodo in path `/opt/docker/pangolin`. Remove after first deployment.

```bash
mkdir config
mkdir config/traefik
# Create Pangolin config.yml
curl -o config/config.yml https://raw.githubusercontent.com/platnub/titan-server/refs/heads/main/docker/containers/pangolin/newt/config/config.yml
## Configure Dashboard URL
sed -i 's|dashboard_url: https://pangolin.example.com|dashboard_url: https://pangolin.domain.my|g' config/config.yml
## Configure Domain
sed -i 's#base_domain: example\.com#base_domain: "domain.my"\n    cert_resolver: "letsencrypt"#' config/config.yml
## Configure Gebril Domain
sed -i 's|base_endpoint: example.com|base_endpoint: "domain.my"|g' config/config.yml
## Configure Secret
key=$(openssl rand 64 | openssl base64 -A)
sed -i "s|secret: my_secret_key|secret: $key|g" config/config.yml
# Create traefik_config.yml
curl -o config/traefik/traefik_config.yml https://raw.githubusercontent.com/platnub/titan-server/refs/heads/main/docker/containers/pangolin/newt/config/traefik/traefik_config.yml
## Configure Email
sed -i 's|email: "mail@example.com"|email: "mail@domain.my"|g' config/traefik/traefik_config.yml
# Create Traefik dynamic_config.yml
curl -o config/traefik/dynamic_config.yml https://raw.githubusercontent.com/platnub/titan-server/refs/heads/main/docker/containers/pangolin/newt/config/traefik/dynamic_config.yml
## Configure Domain
sed -i 's|example.com|domain.my|g' config/traefik/dynamic_config.yml
```
