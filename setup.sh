#!/bin/bash

# Setup script to ensure everything is executable
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Make all scripts executable
chmod +x "$SCRIPT_DIR/toolbox.sh"
chmod +x "$SCRIPT_DIR/install.sh"
[ -f "$SCRIPT_DIR/toolbox" ] && chmod +x "$SCRIPT_DIR/toolbox"
chmod +x "$SCRIPT_DIR/setup.sh"

# Make all library scripts executable too
find "$SCRIPT_DIR/lib" -name "*.sh" -exec chmod +x {} \;

echo "All scripts are now executable"
echo "You can run ./install.sh to install Toolbox TUI to your system"
echo "Or run ./toolbox.sh directly to use it without installation"
