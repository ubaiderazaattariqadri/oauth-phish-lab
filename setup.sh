#!/usr/bin/env bash
set -e

if [ $# -lt 1 ]; then
    echo "Usage: $0 yourdomain.com"
    exit 1
fi

DOMAIN=$1

command -v docker >/dev/null 2>&1 || { echo "Install Docker first"; exit 1; }

if [ ! -f .env ]; then
    echo "ERROR: Create .env file first"
    exit 1
fi

# Check if SSL cert already exists
CERT_DIR="/etc/letsencrypt/live/$DOMAIN"

if docker volume inspect oauth-phish-lab_certs >/dev/null 2>&1; then
    # Check if cert exists in volume
    HAS_CERT=$(docker run --rm -v oauth-phish-lab_certs:/certs alpine ls /certs/live/$DOMAIN/fullchain.pem 2>/dev/null && echo "yes" || echo "no")
else
    HAS_CERT="no"
fi

if [ "$HAS_CERT" = "no" ]; then
    echo "==> Getting SSL certificate..."
    docker compose run --rm --service-ports --entrypoint certbot certbot certonly --standalone \
        -d "$DOMAIN" --agree-tos --email admin@"$DOMAIN" --non-interactive
fi

# Generate nginx config with SSL
echo "==> Generating nginx config..."
cat > nginx-ssl.conf << NGINXEOF
server {
    listen 80 default_server;
    server_name _;
    location / { return 301 https://\$host\$request_uri; }
}

server {
    listen 443 ssl default_server;
    server_name _;
    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;

    location / {
        proxy_pass http://127.0.0.1:5000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
NGINXEOF

cp nginx-ssl.conf nginx.conf

echo "==> Starting containers (detach mode)..."
docker compose up -d --build

echo ""
echo "==> Done! https://$DOMAIN/"
echo "==> Next time just run: docker compose up -d"
echo "==> Redirect URI: https://$DOMAIN/callback"
