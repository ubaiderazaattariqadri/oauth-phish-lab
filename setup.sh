#!/usr/bin/env bash
set -e

if [ $# -lt 1 ]; then
    echo "Usage: $0 yourdomain.com"
    exit 1
fi

DOMAIN=$1

echo "==> Checking requirements..."
command -v docker >/dev/null 2>&1 || { echo "Install Docker first: curl -fsSL https://get.docker.com | sh"; exit 1; }

echo "==> Creating .env from .env.example if missing..."
if [ ! -f .env ]; then
    echo "ERROR: Create .env file first with your CLIENT_ID, CLIENT_SECRET, and REDIRECT_URI"
    echo "Example:"
    echo 'CLIENT_ID=xxx.apps.googleusercontent.com'
    echo 'CLIENT_SECRET=GOCSPX-xxxx'
    echo "REDIRECT_URI=https://$DOMAIN/callback"
    exit 1
fi

echo "==> Getting SSL certificate (standalone mode)..."
docker compose stop app
docker compose run --rm --service-ports certbot certonly --standalone \
    -d "$DOMAIN" \
    --agree-tos --email admin@"$DOMAIN" --non-interactive
docker compose start app

echo "==> Restarting with SSL..."
cat > nginx-ssl.conf << EOF
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
EOF

cp nginx-ssl.conf nginx.conf
docker compose up -d app

echo ""
echo "==> Done! https://$DOMAIN/ par chala gaya"
echo "==> Google Cloud Console mein redirect URI update karna mat bhoolna:"
echo "    https://$DOMAIN/callback"
echo "==> Cert auto-renew ho ga har 12 ghante"
