#!/bin/bash

# Configuration
CONFIG_DIR="$HOME/.toolbox"
DB_FILE="$CONFIG_DIR/commands.json"
EXPORT_DIR="$CONFIG_DIR/exports"

# Color definitions
RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[0;33m"
BLUE="\033[0;34m"
MAGENTA="\033[0;35m"
CYAN="\033[0;36m"
BOLD="\033[1m"
RESET="\033[0m"

# Ensure the toolbox directories exist
mkdir -p "$CONFIG_DIR"
mkdir -p "$EXPORT_DIR"

# Initialize the database file if it doesn't exist
if [ ! -f "$DB_FILE" ]; then
  echo '{"commands":{}}' > "$DB_FILE"
fi
