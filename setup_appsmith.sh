#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

# Function to prompt for user input
prompt_user() {
    read -p "$1: " $2
}

# Prompt for necessary information
prompt_user "Enter your domain name (e.g., example.com)" DOMAIN_NAME
prompt_user "Enter the desired subdomain for Appsmith (e.g., app)" SUBDOMAIN
prompt_user "Enter your email for SSL certificate" SSL_EMAIL

# Install Docker if not already installed
if ! command -v docker &> /dev/null; then
    echo "Docker not found. Installing Docker..."
    sudo apt-get update
    sudo apt-get install -y ca-certificates curl gnupg
    sudo install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    sudo chmod a+r /etc/apt/keyrings/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt-get update
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    sudo usermod -aG docker ${USER}
else
    echo "Docker is already installed."
fi

# Ensure Docker daemon is running
echo "Ensuring Docker daemon is running..."
if ! sudo systemctl is-active --quiet docker; then
    echo "Starting Docker daemon..."
    sudo systemctl start docker
fi

# Wait for Docker daemon to be ready
echo "Waiting for Docker daemon to be ready..."
while ! sudo docker info >/dev/null 2>&1; do
    echo "Waiting for Docker daemon..."
    sleep 1
done
echo "Docker daemon is ready."

# Create appsmith directory
mkdir -p appsmith
cd appsmith

# Create docker-compose.yml file
cat << EOF > docker-compose.yml
version: "3"

services:
  traefik:
    image: "traefik:v2.5"
    container_name: "traefik"
    command:
      - "--api.insecure=true"
      - "--providers.docker=true"
      - "--providers.docker.exposedbydefault=false"
      - "--entrypoints.web.address=:80"
      - "--entrypoints.websecure.address=:443"
      - "--certificatesresolvers.myresolver.acme.tlschallenge=true"
      - "--certificatesresolvers.myresolver.acme.email=${SSL_EMAIL}"
      - "--certificatesresolvers.myresolver.acme.storage=/letsencrypt/acme.json"
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - "/var/run/docker.sock:/var/run/docker.sock:ro"
      - "./letsencrypt:/letsencrypt"
    networks:
      - appsmith-network

  appsmith:
    image: index.docker.io/appsmith/appsmith-ee
    container_name: appsmith
    expose:
      - "80"
    volumes:
      - ./stacks:/appsmith-stacks
    restart: unless-stopped
    networks:
      - appsmith-network
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.appsmith.rule=Host(\`${SUBDOMAIN}.${DOMAIN_NAME}\`)"
      - "traefik.http.routers.appsmith.entrypoints=websecure"
      - "traefik.http.routers.appsmith.tls.certresolver=myresolver"

networks:
  appsmith-network:
    driver: bridge
EOF

# Create the necessary directories
mkdir -p stacks letsencrypt

# Start the Docker containers
sudo docker-compose up -d

echo "Appsmith setup complete. It should now be accessible at https://${SUBDOMAIN}.${DOMAIN_NAME}"
echo "Please allow a few minutes for the server to fully start up and for SSL certificates to be issued."
echo "After the server is up, open https://${SUBDOMAIN}.${DOMAIN_NAME} in your browser to set up your administrator account."