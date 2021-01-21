#!/bin/bash

set -o xtrace

# https://github.com/internetarchive/openlibrary/wiki/Deployment-Scratchpad

# This script must be run on ol-home0 to start a new deployment.

echo "Starting production deployment at $(date)"
export HOSTNAME="${HOSTNAME:-$HOST}"
if [[ $HOSTNAME != ol-home0.* ]]; then
    echo "FATAL: Must only be run on ol-home0" ;
    exit 1 ;
fi

# `sudo git pull origin master` the core Open Library repos:
# 1. https://github.com/internetarchive/olsystem
# 2. https://git.archive.org/jake/booklending_utils
# 3. https://github.com/internetarchive/openlibrary
# 4. https://github.com/internetarchive/infogami

### Needed to log into BOOKLENDING_UTILS

REPO_DIRS="/opt/olsystem /opt/booklending_utils /opt/openlibrary /opt/openlibrary/vendor/infogami"
for REPO_DIR in $REPO_DIRS
do
    cd $REPO_DIR
    sudo git pull origin master
done

# These commands were run once and probably do not need to be repeated
sudo mkdir -p /opt/olimages
sudo chown root:staff /opt/olimages
sudo chmod g+w /opt/olimages
sudo chmod g+s /opt/olimages
docker image prune -f

# Build the oldev Docker production image
cd /opt/openlibrary
export COMPOSE_FILE="docker-compose.yml:docker-compose.production.yml"
time docker-compose build --pull web
docker-compose run -uroot --rm home make i18n

# Compress the image in a .tar.gz file for transfer to other hosts
cd /opt/olimages
time docker save oldev:latest | gzip > oldev_latest.tar.gz

# Transfer the .tar.gz image and four repo dirs to other hosts
SERVERS="ol-covers0 ol-web1 ol-web2"
for SERVER in $SERVERS
do
    echo "Starting rsync of oldev_latest.tar.gz to $REMOTE_HOST..."
    time rsync -a --no-owner --group --verbose oldev_latest.tar.gz "$SERVER:/opt/olimages/"
    if [[ $HOSTNAME == ol-web* ]]; then
        REPO_DIRS="/opt/olsystem /opt/booklending_utils /opt/openlibrary /opt/openlibrary/vendor/infogami"
    else
        REPO_DIRS="/opt/olsystem /opt/openlibrary /opt/openlibrary/vendor/infogami"
    fi
    for REPO_DIR in $REPO_DIRS
    do
        echo "Starting rsync of $REPO_DIR to $SERVER..."
        time rsync -a -r --no-owner --group --verbose $REPO_DIR "$SERVER:$REPO_DIR"
    done
    echo -e "Finished rsync to $SERVER...\n"
done

# Uncompress and tag oldev_latest.tar.gz that we have rsynced over
bash /opt/openlibrary/scripts/deployment/continue_production_deployment.sh
for SERVER in $SERVERS
do
    ssh $SERVERS /opt/openlibrary/scripts/deployment/continue_production_deployment.sh
done

echo "Finished production deployment at $(date)"
echo "To reboot the servers, please run scripts/deployments/restart_all_servers.sh"
