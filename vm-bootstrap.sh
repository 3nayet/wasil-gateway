#!/usr/bin/env bash
# One-shot VM bootstrap for the wasil alpha deployment.
# Run as root on a fresh Ubuntu 24.04 VM:
#   curl -fsSL https://raw.githubusercontent.com/3nayet/wasil-gateway/master/vm-bootstrap.sh | bash
# or scp + sudo bash vm-bootstrap.sh
set -euo pipefail

DEPLOY_USER=deploy
APP_DIR=/opt/wasil

if [ "$(id -u)" -ne 0 ]; then echo "must run as root"; exit 1; fi

apt-get update
apt-get install -y ca-certificates curl gnupg ufw git

# create deploy user with same authorized_keys as root
if ! id -u "$DEPLOY_USER" >/dev/null 2>&1; then
    adduser --disabled-password --gecos "" "$DEPLOY_USER"
fi
usermod -aG sudo "$DEPLOY_USER"
mkdir -p "/home/$DEPLOY_USER/.ssh"
if [ -f /root/.ssh/authorized_keys ]; then
    cp /root/.ssh/authorized_keys "/home/$DEPLOY_USER/.ssh/authorized_keys"
fi
chown -R "$DEPLOY_USER:$DEPLOY_USER" "/home/$DEPLOY_USER/.ssh"
chmod 700 "/home/$DEPLOY_USER/.ssh"
chmod 600 "/home/$DEPLOY_USER/.ssh/authorized_keys" || true

# docker
if ! command -v docker >/dev/null 2>&1; then
    curl -fsSL https://get.docker.com | sh
fi
usermod -aG docker "$DEPLOY_USER"
systemctl enable --now docker

# app dir
mkdir -p "$APP_DIR"
chown "$DEPLOY_USER:$DEPLOY_USER" "$APP_DIR"

# host firewall (defence-in-depth on top of Hetzner Cloud Firewall)
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp
ufw allow 5432/tcp   # public Postgres per ops decision
ufw --force enable

cat <<EOF

Bootstrap complete.

Next steps (as the $DEPLOY_USER user):
  su - $DEPLOY_USER
  cd $APP_DIR
  git clone https://github.com/3nayet/wasil-gateway.git checkout
  cp checkout/docker-compose.prod.yml ./docker-compose.yml
  mkdir -p gateway caddy
  cp checkout/nginx.prod.conf gateway/nginx.prod.conf
  cp checkout/Caddyfile      caddy/Caddyfile
  # Create .env from wasil-be/.env.example and fill in real secrets:
  curl -fsSL https://raw.githubusercontent.com/3nayet/wasil-be/master/.env.example -o .env
  \$EDITOR .env
  docker login ghcr.io -u 3nayet   # PAT with read:packages
  docker compose pull
  docker compose up -d
EOF
