#!/bin/bash

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Prompt for domain name
read -p "Enter your domain name (e.g., example.com): " DOMAIN

# Update system
echo "Updating system..."
sudo apt update && sudo apt upgrade -y

# Install Docker if not already installed
if ! command_exists docker; then
    echo "Installing Docker..."
    sudo apt install -y docker.io
    sudo systemctl enable --now docker
fi

# Install Nginx and Certbot
echo "Installing Nginx and Certbot..."
sudo apt install -y nginx certbot python3-certbot-nginx

# Create Docker network
echo "Creating Docker network..."
docker network create n8n_network

# Create Nginx config
echo "Configuring Nginx..."
sudo tee /etc/nginx/sites-available/n8n << EOF
server {
    listen 80;
    server_name $DOMAIN;

    location / {
        proxy_pass http://localhost:5678;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

# Enable Nginx config
sudo ln -s /etc/nginx/sites-available/n8n /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx

# Obtain SSL certificate
echo "Obtaining SSL certificate..."
sudo certbot --nginx -d $DOMAIN --non-interactive --agree-tos --email webmaster@$DOMAIN --redirect

# Run n8n Docker container
echo "Starting n8n Docker container..."
docker run -d \
  --name n8n \
  --restart unless-stopped \
  --network n8n_network \
  -p 5678:5678 \
  -e N8N_HOST="$DOMAIN" \
  -e N8N_PORT="443" \
  -e N8N_PROTOCOL="https" \
  -v ~/.n8n:/home/node/.n8n \
  n8nio/n8n

echo "Setup complete! Your n8n instance should now be accessible at https://$DOMAIN"
echo "Please ensure your domain's DNS A record points to this server's IP address."
echo "If you encounter any issues, check your server's firewall settings and ensure ports 80 and 443 are open."
