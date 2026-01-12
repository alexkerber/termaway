#!/bin/bash
# Deploy website to production server
# Uses SSH key authentication - configure host in ~/.ssh/config

set -e

# Configuration
REMOTE_USER="${TERMAWAY_USER:-root}"
REMOTE_HOST="${TERMAWAY_HOST:-alexkerber.com}"
REMOTE_PATH="/var/www/termaway"
LOCAL_PATH="website/"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}Deploying website to ${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_PATH}${NC}"

# Sync website files
rsync -avz --delete \
    --exclude '.DS_Store' \
    --exclude '*.swp' \
    "$LOCAL_PATH" \
    "${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_PATH}/"

echo -e "${GREEN}Deploy complete!${NC}"
