#!/bin/bash

# Toolbox installation script
# This script installs the Toolbox command shortcut manager to your system

# Set text colors
RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[0;33m"
CYAN="\033[0;36m"
BOLD="\033[1m"
RESET="\033[0m"

# Get the directory where the script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Determine installation path based on system
install_system_wide() {
    echo -e "${YELLOW}Installing Toolbox system-wide (requires sudo access)${RESET}"
    
    # Create directories
    sudo mkdir -p "/usr/local/share/toolbox/lib"
    
    # Copy library files
    sudo cp -r "$SCRIPT_DIR/lib/"* "/usr/local/share/toolbox/lib/"
    
    # Copy and make main script executable
    sudo cp "$SCRIPT_DIR/toolbox.sh" "/usr/local/bin/toolbox"
    sudo chmod +x "/usr/local/bin/toolbox"
    
    echo -e "${GREEN}${BOLD}✓ Toolbox installed system-wide!${RESET}"
    echo -e "You can run it by typing ${CYAN}toolbox${RESET} in your terminal."
}

install_user() {
    echo -e "${YELLOW}Installing Toolbox for current user only${RESET}"
    
    # Create directories
    mkdir -p "$HOME/.local/share/toolbox/lib"
    mkdir -p "$HOME/.local/bin"
    
    # Copy library files
    cp -r "$SCRIPT_DIR/lib/"* "$HOME/.local/share/toolbox/lib/"
    
    # Copy and make main script executable
    cp "$SCRIPT_DIR/toolbox.sh" "$HOME/.local/bin/toolbox"
    chmod +x "$HOME/.local/bin/toolbox"
    
    # Update PATH if needed
    if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
        echo -e "${YELLOW}Adding $HOME/.local/bin to your PATH${RESET}"
        
        # Detect shell
        SHELL_NAME=$(basename "$SHELL")
        
        if [[ "$SHELL_NAME" == "bash" ]]; then
            # For Bash
            echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
            echo -e "${GREEN}Added PATH to .bashrc. Please restart your terminal or run 'source ~/.bashrc'${RESET}"
        elif [[ "$SHELL_NAME" == "zsh" ]]; then
            # For Zsh
            echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.zshrc"
            echo -e "${GREEN}Added PATH to .zshrc. Please restart your terminal or run 'source ~/.zshrc'${RESET}"
        else
            echo -e "${YELLOW}Please manually add $HOME/.local/bin to your PATH${RESET}"
        fi
    fi
    
    echo -e "${GREEN}${BOLD}✓ Toolbox installed for current user!${RESET}"
    echo -e "You can run it by typing ${CYAN}toolbox${RESET} in your terminal."
}

# Show welcome message
echo -e "$(gum style --border normal --margin "1" --padding "1 2" --border-foreground "#36a3ff" "Welcome to Toolbox - Command Shortcut Manager")"

# Check if script is running from the correct directory
if [ ! -d "$SCRIPT_DIR/lib" ] || [ ! -f "$SCRIPT_DIR/toolbox.sh" ]; then
    echo -e "${RED}ERROR: Cannot find required files.${RESET}"
    echo "Please run this script from the Toolbox_TUI directory."
    exit 1
fi

# Check for dependencies
echo -e "${YELLOW}Checking dependencies...${RESET}"

# Check for jq
if ! command -v jq &> /dev/null; then
    echo -e "${RED}Error: jq is required but not installed.${RESET}"
    echo "Please install jq before continuing."
    echo "On macOS with Homebrew: brew install jq"
    echo "On Debian/Ubuntu: sudo apt install jq"
    exit 1
fi

# Check for gum
if ! command -v gum &> /dev/null; then
    echo -e "${YELLOW}Warning: gum is not installed.${RESET}"
    echo "Gum is recommended for the best TUI experience."
    echo "Installation instructions:"
    echo "On macOS with Homebrew: brew install gum"
    echo "On Linux/macOS with Go: go install github.com/charmbracelet/gum@latest"
    echo -e "${YELLOW}Would you like to continue without gum? TUI features may not work correctly.${RESET}"
    read -p "Continue? (y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Ask for installation type
echo -e "${BOLD}Choose installation type:${RESET}"
echo "1) System-wide (requires sudo, available to all users)"
echo "2) User only (no sudo required, only available to current user)"
echo -e "${YELLOW}NOTE: Press Ctrl+C at any time to cancel installation${RESET}"
read -p "Enter choice [1-2]: " choice

case $choice in
    1)
        install_system_wide
        ;;
    2)
        install_user
        ;;
    *)
        echo -e "${RED}Invalid choice. Installation cancelled.${RESET}"
        exit 1
        ;;
esac

echo
echo -e "${GREEN}${BOLD}Installation completed!${RESET}"
echo "Type 'toolbox' to get started, or 'toolbox help' for usage information."
