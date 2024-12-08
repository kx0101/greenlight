#!/bin/bash
set -eu

# ==================================================================================== #
# VARIABLES
# ==================================================================================== #

TIMEZONE=Europe/Athens

USERNAME=greenlight

read -p "Enter password for greenlight DB user: " DB_PASSWORD

export LC_ALL=en_US.UTF-8

# ==================================================================================== #
# SCRIPT LOGIC
# ==================================================================================== #

# Enable the "universe" repository.
add-apt-repository --yes universe

# Update all software packages.
apt update

# Set the system timezone and install all locales
timedatectl set-timezone ${TIMEZONE}
apt --yes install locales-all

# Check if the user exists before adding
if id -u "${USERNAME}" >/dev/null 2>&1; then
    echo "User '${USERNAME}' already exists. Skipping user creation."
else
    # Add the new user (and give them sudo privileges)
    useradd --create-home --shell "/bin/bash" --groups sudo "${USERNAME}"

    # Force a password to be set for the new user the first time they log in
    passwd --delete "${USERNAME}"
    chage --lastday 0 "${USERNAME}"

    # Copy the SSH keys from the root user to the new user
    rsync --archive --chown=${USERNAME}:${USERNAME} /root/.ssh /home/${USERNAME}
fi

# Force a password to be set for the new user the first time they log in
passwd --delete "${USERNAME}"
chage --lastday 0 "${USERNAME}"

# Copy the SSH keys from the root user to the new user
rsync --archive --chown=${USERNAME}:${USERNAME} /root/.ssh /home/${USERNAME}

# Configure the firewall to allow SSH, HTTP and HTTPS traffic
ufw allow 22
ufw allow 80/tcp
ufw allow 443/tcp
ufw --force enable

# Install fail2ban
apt --yes install fail2ban

# Install the migrate CLI tool
curl -L https://github.com/golang-migrate/migrate/releases/download/v4.14.1/migrate.linux-amd64.tar.gz | tar xvz
mv migrate.linux-amd64 /usr/local/bin/migrate

# Add the official postgresql repository to the APT because its not included in the ubuntu default repo
sudo sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list'
wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo apt-key add -
sudo apt-get update -y

# Install PostgreSQL 14
sudo apt --yes install postgresql-14

# Set up the greenlight DB and create a user account with the password entered earlier
# Check if the database 'greenlight' exists
if sudo -i -u postgres psql -lqt | cut -d \| -f 1 | grep -qw greenlight; then
    echo "Database 'greenlight' already exists. Skipping creation."
else
    sudo -i -u postgres psql -c "CREATE DATABASE greenlight"
    sudo -i -u postgres psql -d greenlight -c "CREATE EXTENSION IF NOT EXISTS citext"
    echo "Database 'greenlight' created successfully."
fi

# Check if the role 'greenlight' exists
if sudo -i -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='greenlight'" | grep -q 1; then
    echo "Role 'greenlight' already exists. Skipping creation."
else
    sudo -i -u postgres psql -d greenlight -c "CREATE ROLE greenlight WITH LOGIN PASSWORD '${DB_PASSWORD}'"
    echo "Role 'greenlight' created successfully."
fi

# Add a DSN for connecting to the greenlight database
echo "GREENLIGHT_DB_DSN='postgres://greenlight:${DB_PASSWORD}@localhost/greenlight'" >> /etc/environment

# Install Caddy
apt install -y debian-keyring debian-archive-keyring apt-transport-https
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | sudo tee /etc/apt/sources.list.d/caddy-stable.list
apt update
apt --yes install caddy

# Upgrade all packages.
apt --yes -o Dpkg::Options::="--force-confnew" upgrade

echo "Script complete! Rebooting..."
reboot
