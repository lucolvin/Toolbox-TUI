#!/bin/bash

# Function to check if jq is installed
check_dependencies() {
  if ! command -v jq &> /dev/null; then
    echo -e "${RED}Error: jq is required but not installed.${RESET}"
    echo "Please install jq to use Toolbox."
    echo "On Debian/Ubuntu: sudo apt install jq"
    echo "On macOS with Homebrew: brew install jq"
    echo "On Fedora: sudo dnf install jq"
    exit 1
  fi
  
  # Check if gum is installed
  if ! command -v gum &> /dev/null; then
    echo -e "${YELLOW}Warning: gum is not installed. This is required for TUI features.${RESET}"
    echo "Please install gum for the best experience:"
    echo "On macOS with Homebrew: brew install gum"
    echo "On Linux/macOS with Go: go install github.com/charmbracelet/gum@latest"
    echo "Or visit: https://github.com/charmbracelet/gum#installation"
    echo
    read -p "$(echo -e "${YELLOW}Do you want to continue without gum? (y/N):${RESET} ")" confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
      exit 1
    fi
  fi
}

# Function to check if gum is installed (needed for TUI mode)
check_gum() {
  if ! command -v gum &> /dev/null; then
    echo -e "${RED}Error: gum is required for TUI mode but not installed.${RESET}"
    echo "Please install gum to use the TUI features."
    echo "On macOS with Homebrew: brew install gum"
    echo "On Linux/macOS with Go: go install github.com/charmbracelet/gum@latest"
    echo "Or visit: https://github.com/charmbracelet/gum#installation"
    return 1
  fi
  return 0
}

# Function to hide cursor
hide_cursor() {
  tput civis
}

# Function to show cursor
show_cursor() {
  tput cnorm
}

# Function for custom menu with proper vim keybindings
display_menu() {
  local title="$1"
  shift
  local options=("$@")
  local selected=0
  local key
  local ARROW_UP=$'\e[A'
  local ARROW_DOWN=$'\e[B'
  
  # Save cursor position
  tput sc
  
  while true; do
    # Clear previous menu (restore cursor position)
    tput rc
    tput ed
    
    # Print title
    echo -e "${CYAN}${BOLD}$title${RESET}"
    echo -e "${CYAN}─────────────────────${RESET}"
    echo -e "${YELLOW}Use j/k or arrow keys to navigate, Enter to select, q to quit${RESET}"
    echo
    
    # Display menu options
    for i in "${!options[@]}"; do
      if [ $i -eq $selected ]; then
        echo -e "${GREEN}${BOLD}> ${options[$i]}${RESET}"
      else
        echo -e "  ${options[$i]}"
      fi
    done
    
    # Read a single key press
    read -rsn1 key
    
    # Handle ESC sequences for arrow keys
    if [[ $key == $'\e' ]]; then
      read -rsn2 -t 0.1 rest
      key="$key$rest"
    fi
    
    case "$key" in
      'j'|$ARROW_DOWN)  # Down
        selected=$((selected + 1))
        if [ $selected -ge ${#options[@]} ]; then
          selected=$((${#options[@]} - 1))
        fi
        ;;
      'k'|$ARROW_UP)  # Up
        selected=$((selected - 1))
        if [ $selected -lt 0 ]; then
          selected=0
        fi
        ;;
      'q'|$'\e')  # Escape or 'q'
        echo
        return 255
        ;;
      '')  # Enter
        echo
        return $selected
        ;;
    esac
  done
}

# Function to show usage information
show_usage() {
  echo -e "${BOLD}${CYAN}Usage:${RESET} toolbox COMMAND [ARGS]"
  echo
  echo -e "${BOLD}${CYAN}Commands:${RESET}"
  echo -e "  ${YELLOW}add${RESET} NAME COMMAND [-d DESCRIPTION] [-c CATEGORY]"
  echo -e "                           Add a new command shortcut"
  echo -e "  ${YELLOW}list${RESET} [-c CATEGORY] [-s SEARCH]"
  echo -e "                           List saved commands"
  echo -e "  ${YELLOW}run${RESET} NAME                 Run a saved command"
  echo -e "  ${YELLOW}delete${RESET} NAME              Delete a command"
  echo -e "  ${YELLOW}modify${RESET} NAME [-cmd COMMAND] [-d DESCRIPTION] [-c CATEGORY]"
  echo -e "                           Modify an existing command"
  echo -e "  ${YELLOW}categories${RESET}               List all available categories"
  echo -e "  ${YELLOW}export${RESET} [FILENAME] [-c CATEGORY]"
  echo -e "                           Export commands to a file"
  echo -e "  ${YELLOW}import${RESET} FILENAME          Import commands from a file"
  echo -e "  ${YELLOW}help${RESET}                     Show this help message"
  echo
  echo -e "${BOLD}${CYAN}Examples:${RESET}"
  echo -e "  toolbox"
  echo -e "  toolbox add list-ports \"lsof -i -P -n | grep LISTEN\" -d \"List all listening ports\" -c \"network\""
  echo -e "  toolbox list"
  echo -e "  toolbox list -c network"
  echo -e "  toolbox run list-ports"
  echo -e "  toolbox export my_commands -c system"
  echo -e "  toolbox import my_commands.json"
}
