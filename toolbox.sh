#!/bin/bash

# Toolbox - A terminal tool for managing command shortcuts
# Usage: toolbox command [arguments]

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

# Function to display the Toolbox logo
show_logo() {
  echo -e "${CYAN}"
  echo '  _______          _ _               '
  echo ' |__   __|        | | |              '
  echo '    | | ___   ___ | | |__   _____  __'
  echo '    | |/ _ \ / _ \| | '"'"'_ \ / _ \ \/ /'
  echo '    | | (_) | (_) | | |_) | (_) >  < '
  echo '    |_|\___/ \___/|_|_.__/ \___/_/\_\'
  echo -e "${RESET}"
  echo -e "${YELLOW}Command Shortcut Manager${RESET}"
  echo
}

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
}

# Function to check if fzf is installed (needed for TUI mode)
check_fzf() {
  if ! command -v fzf &> /dev/null; then
    echo -e "${RED}Error: fzf is required for TUI mode but not installed.${RESET}"
    echo "Please install fzf to use the TUI features."
    echo "On macOS with Homebrew: brew install fzf"
    echo "On Debian/Ubuntu: sudo apt install fzf"
    echo "Or visit: https://github.com/junegunn/fzf#installation"
    return 1
  fi
  return 0
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

# Full screen terminal UI mode
run_tui_mode() {
  # First check if fzf is installed (still needed for command browsing)
  if ! check_fzf; then
    echo -e "${YELLOW}FZF is required for command browsing in TUI mode.${RESET}"
    echo -e "${YELLOW}Falling back to basic interactive mode.${RESET}"
    sleep 2
    interactive_add
    return
  fi
  
  # Clear screen and show header
  clear
  show_logo
  
  # Menu options
  local options=(
    "View/Run Commands"
    "Add New Command"
    "Modify Command"
    "Delete Command"
    "Export Commands"
    "Import Commands"
    "Quit"
  )
  
  # Display custom menu
  display_menu "Toolbox TUI Mode" "${options[@]}"
  local menu_status=$?
  
  # Handle menu selection
  if [ $menu_status -eq 255 ]; then
    # User pressed escape or 'q'
    echo -e "${GREEN}Exiting TUI mode.${RESET}"
    return
  elif [ $menu_status -lt ${#options[@]} ]; then
    case $menu_status in
      0) tui_view_commands ;;
      1) tui_add_command ;;
      2) tui_modify_command ;;
      3) tui_delete_command ;;
      4) tui_export_commands ;;
      5) tui_import_commands ;;
      6) echo -e "${GREEN}Exiting TUI mode.${RESET}"; return ;;
    esac
  fi
  
  # Return to TUI mode after an action completes (recursive)
  run_tui_mode
}

# Function to view commands using a custom browse interface with vim-like navigation
tui_browse_commands() {
  # Check if there are any commands
  command_count=$(jq '.commands | length' "$DB_FILE")
  if [ "$command_count" -eq 0 ]; then
    echo -e "${YELLOW}No commands found. Add some first.${RESET}"
    read -n 1 -s -r -p "Press any key to continue..."
    return
  fi
  
  # Create a temporary file that combines command name, description, and category
  tmp_file=$(mktemp)
  jq -r '.commands | to_entries[] | "\(.key)|\(.value.category)|\(.value.description)|\(.value.command)"' "$DB_FILE" > "$tmp_file"
  
  # Get number of commands
  command_count=$(wc -l < "$tmp_file")
  
  # For now, still use fzf for command browsing as it has powerful search capabilities
  # But provide a note about the vim keybindings
  echo -e "${CYAN}${BOLD}Select a command to run:${RESET}"
  echo -e "${YELLOW}In command browser: /${RESET}${GREEN}search term${RESET}${YELLOW} to search, j/k to navigate${RESET}"
  
  local selection
  selection=$(cat "$tmp_file" | 
    fzf --layout=reverse --height 100% --border \
        --prompt="Select command to run: " \
        --preview 'echo -e "\033[1;36mCommand:\033[0m {1}\n\033[1;33mCategory:\033[0m {2}\n\033[1;32mDescription:\033[0m {3}\n\033[1;34mCommand to run:\033[0m {4}"' \
        --preview-window=right:40% \
        --bind="ctrl-r:reload(cat \"$tmp_file\")" \
        --bind="ctrl-q:abort" \
        --header="j/k: Navigate | Enter: Select | q/ESC: Back | /: Search | ctrl-r: Refresh" \
        --delimiter="|" \
        --with-nth=1,2,3)
  
  # Clean up
  rm "$tmp_file"
  
  # Return the selection
  echo "$selection"
}

# Function to view and run commands in TUI mode
tui_view_commands() {
  local selection=$(tui_browse_commands)
  
  # If no selection, return
  if [ -z "$selection" ]; then
    return
  fi
  
  # Parse the selection to get the command name
  local cmd_name=$(echo "$selection" | cut -d'|' -f1)
  
  # Get the command to run
  local command_to_run=$(jq -r ".commands[\"$cmd_name\"].command" "$DB_FILE")
  
  # Ask for confirmation before running
  clear
  echo -e "${CYAN}About to run:${RESET} ${GREEN}$command_to_run${RESET}"
  
  # Use custom confirmation dialog
  local confirm_options=("Yes, run this command" "No, cancel")
  display_menu "Run Command?" "${confirm_options[@]}"
  local confirm_status=$?
  
  if [ $confirm_status -eq 0 ]; then
    # Clear screen for command output
    clear
    echo -e "${CYAN}Running: ${GREEN}$command_to_run${RESET}"
    echo -e "${YELLOW}─────────────────────────────────────${RESET}"
    eval "$command_to_run"
    echo -e "${YELLOW}─────────────────────────────────────${RESET}"
    echo -e "${GREEN}Command execution completed.${RESET}"
    echo
    read -n 1 -s -r -p "Press any key to continue..."
  fi
}

# Function for category selection with vim keybindings
select_category() {
  local title="$1"
  local include_all="${2:-true}"
  local include_new="${3:-true}"
  
  # Get available categories
  local available_categories=$(jq -r '.commands | map(.category) | unique | .[]' "$DB_FILE" 2>/dev/null | sort)
  
  if [ -z "$available_categories" ]; then
    if [ "$include_new" = "true" ]; then
      echo "general"
      return 0
    else
      return 1
    fi
  fi
  
  # Create array of options
  local options=()
  
  if [ "$include_all" = "true" ]; then
    options+=("All Categories")
  fi
  
  # Add each category as an option
  while IFS= read -r category; do
    options+=("$category")
  done <<< "$available_categories"
  
  if [ "$include_new" = "true" ]; then
    options+=("[New Category]")
  fi
  
  # Display menu
  display_menu "$title" "${options[@]}"
  local menu_status=$?
  
  if [ $menu_status -eq 255 ]; then
    # User cancelled
    return 1
  fi
  
  # Calculate index based on whether "All Categories" is included
  local selected_category
  
  if [ "$include_all" = "true" ]; then
    if [ $menu_status -eq 0 ]; then
      # All Categories selected
      echo ""
      return 0
    elif [ $menu_status -eq ${#options[@]} ]; then
      # New Category selected
      read -p "$(echo -e "${YELLOW}Enter new category name:${RESET} ")" new_category
      echo "${new_category:-general}"
      return 0
    else
      # Regular category selected
      selected_category="${options[$menu_status]}"
    fi
  else
    if [ $menu_status -eq $((${#options[@]}-1)) ] && [ "$include_new" = "true" ]; then
      # New Category selected
      read -p "$(echo -e "${YELLOW}Enter new category name:${RESET} ")" new_category
      echo "${new_category:-general}"
      return 0
    else
      # Regular category selected
      selected_category="${options[$menu_status]}"
    fi
  fi
  
  echo "$selected_category"
  return 0
}

# Function to add a command in TUI mode
tui_add_command() {
  clear
  echo -e "${CYAN}${BOLD}Add a New Command${RESET}"
  echo -e "${CYAN}─────────────────────${RESET}"
  
  # Command name (required)
  read -p "$(echo -e "${YELLOW}Command name:${RESET} ")" name
  if [ -z "$name" ]; then
    echo -e "${RED}Error: Command name cannot be empty.${RESET}"
    read -n 1 -s -r -p "Press any key to continue..."
    return
  fi
  
  # Check if command already exists
  if jq -e ".commands[\"$name\"]" "$DB_FILE" > /dev/null 2>&1; then
    echo -e "${YELLOW}Command '$name' already exists. Use modify to update it.${RESET}"
    read -n 1 -s -r -p "Press any key to continue..."
    return
  fi
  
  # Command to run (required)
  read -p "$(echo -e "${YELLOW}Command to run:${RESET} ")" command_to_run
  if [ -z "$command_to_run" ]; then
    echo -e "${RED}Error: Command to run cannot be empty.${RESET}"
    read -n 1 -s -r -p "Press any key to continue..."
    return
  fi
  
  # Description (optional)
  read -p "$(echo -e "${YELLOW}Description (optional):${RESET} ")" description
  
  # Select category using vim-like navigation
  category=$(select_category "Select Category for Command" false true)
  status=$?
  
  if [ $status -ne 0 ]; then
    echo -e "${YELLOW}Command addition cancelled.${RESET}"
    read -n 1 -s -r -p "Press any key to continue..."
    return
  fi
  
  # Add the command
  add_command "$name" "$command_to_run" "$description" "$category"
  read -n 1 -s -r -p "Press any key to continue..."
}

# Function to modify a command in TUI mode
tui_modify_command() {
  # Check if there are any commands
  command_count=$(jq '.commands | length' "$DB_FILE")
  if [ "$command_count" -eq 0 ]; then
    echo -e "${YELLOW}No commands found to modify.${RESET}"
    read -n 1 -s -r -p "Press any key to continue..."
    return
  fi
  
  # Create a temporary file that combines command name, description, and category
  tmp_file=$(mktemp)
  jq -r '.commands | to_entries[] | "\(.key)|\(.value.category)|\(.value.description)|\(.value.command)"' "$DB_FILE" > "$tmp_file"
  
  # Choose a command to modify using fzf
  clear
  echo -e "${CYAN}${BOLD}Modify a Command${RESET}"
  echo -e "${CYAN}─────────────────────${RESET}"
  
  local selection
  selection=$(cat "$tmp_file" | 
    fzf --layout=reverse --height 100% --border \
        --prompt="Select command to modify: " \
        --preview 'echo -e "\033[1;36mCommand:\033[0m {1}\n\033[1;33mCategory:\033[0m {2}\n\033[1;32mDescription:\033[0m {3}\n\033[1;34mCommand to run:\033[0m {4}"' \
        --preview-window=right:40% \
        --bind="ctrl-q:abort" \
        --header="↑/↓:Navigate | Enter:Select | ESC/ctrl-q:Back" \
        --delimiter="|" \
        --with-nth=1,2,3)
  
  # Clean up
  rm "$tmp_file"
  
  # If no selection, return
  if [ -z "$selection" ]; then
    return
  fi
  
  # Parse the selection to get the command name
  local name=$(echo "$selection" | cut -d'|' -f1)
  
  # Get current values
  local current_command=$(jq -r ".commands[\"$name\"].command" "$DB_FILE")
  local current_description=$(jq -r ".commands[\"$name\"].description" "$DB_FILE")
  local current_category=$(jq -r ".commands[\"$name\"].category" "$DB_FILE")
  
  clear
  echo -e "${CYAN}${BOLD}Modifying Command: ${RESET}${GREEN}$name${RESET}"
  echo -e "${CYAN}─────────────────────────${RESET}"
  
  # Show current command and ask for new one
  echo -e "${CYAN}Current command:${RESET} ${GREEN}$current_command${RESET}"
  read -p "$(echo -e "${YELLOW}New command (leave empty to keep current):${RESET} ")" new_command
  local command_to_use="${new_command:-$current_command}"
  
  # Show current description and ask for new one
  echo -e "${CYAN}Current description:${RESET} ${YELLOW}$current_description${RESET}"
  read -p "$(echo -e "${YELLOW}New description (leave empty to keep current):${RESET} ")" new_description
  local description_to_use="${new_description:-$current_description}"
  
  # Show current category and available categories
  echo -e "${CYAN}Current category:${RESET} ${MAGENTA}$current_category${RESET}"
  
  # Select category using vim-like navigation
  category=$(select_category "Select New Category for Command" false true)
  status=$?
  
  if [ $status -ne 0 ]; then
    echo -e "${YELLOW}Command modification cancelled.${RESET}"
    read -n 1 -s -r -p "Press any key to continue..."
    return
  fi
  
  # Update the command
  jq --arg name "$name" \
     --arg cmd "$command_to_use" \
     --arg desc "$description_to_use" \
     --arg cat "$category" \
     '.commands[$name] = {"command": $cmd, "description": $desc, "category": $cat}' \
     "$DB_FILE" > "$DB_FILE.tmp" && mv "$DB_FILE.tmp" "$DB_FILE"
  
  echo -e "${GREEN}✓ Command '${BOLD}$name${RESET}${GREEN}' updated successfully.${RESET}"
  read -n 1 -s -r -p "Press any key to continue..."
}

# Function to delete a command in TUI mode
tui_delete_command() {
  # Check if there are any commands
  command_count=$(jq '.commands | length' "$DB_FILE")
  if [ "$command_count" -eq 0 ]; then
    echo -e "${YELLOW}No commands found to delete.${RESET}"
    read -n 1 -s -r -p "Press any key to continue..."
    return
  fi
  
  # Create a temporary file that combines command name, description, and category
  tmp_file=$(mktemp)
  jq -r '.commands | to_entries[] | "\(.key)|\(.value.category)|\(.value.description)|\(.value.command)"' "$DB_FILE" > "$tmp_file"
  
  # Choose a command to delete using fzf
  clear
  echo -e "${CYAN}${BOLD}Delete a Command${RESET}"
  echo -e "${CYAN}─────────────────────${RESET}"
  
  local selection
  selection=$(cat "$tmp_file" | 
    fzf --layout=reverse --height 100% --border --multi \
        --prompt="Select command(s) to delete (TAB to multi-select): " \
        --preview 'echo -e "\033[1;36mCommand:\033[0m {1}\n\033[1;33mCategory:\033[0m {2}\n\033[1;32mDescription:\033[0m {3}\n\033[1;34mCommand to run:\033[0m {4}"' \
        --preview-window=right:40% \
        --bind="ctrl-q:abort" \
        --header="↑/↓:Navigate | TAB:Select multiple | Enter:Delete | ESC/ctrl-q:Back" \
        --delimiter="|" \
        --with-nth=1,2,3)
  
  # Clean up
  rm "$tmp_file"
  
  # If no selection, return
  if [ -z "$selection" ]; then
    return
  fi
  
  # Process each selected command
  echo "$selection" | while IFS="|" read -r cmd_name category description command_to_run
  do
    # Confirm deletion
    clear
    echo -e "${RED}${BOLD}Confirm Deletion${RESET}"
    echo -e "${YELLOW}About to delete:${RESET}"
    echo -e "  ${CYAN}${BOLD}$cmd_name${RESET}"
    [ -n "$description" ] && echo -e "  ${YELLOW}$description${RESET}"
    echo -e "  ${GREEN}$ $command_to_run${RESET}"
    
    read -p "$(echo -e "${RED}Are you sure you want to delete this command? (y/N):${RESET} ")" confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
      # Delete the command
      jq --arg name "$cmd_name" 'del(.commands[$name])' "$DB_FILE" > "$DB_FILE.tmp" && mv "$DB_FILE.tmp" "$DB_FILE"
      echo -e "${GREEN}✓ Command '${BOLD}$cmd_name${RESET}${GREEN}' deleted successfully.${RESET}"
    else
      echo -e "${YELLOW}Deletion cancelled for '$cmd_name'.${RESET}"
    fi
    
    echo
    sleep 1
  done
  
  read -n 1 -s -r -p "Press any key to continue..."
}

# Function to export commands in TUI mode
tui_export_commands() {
  clear
  echo -e "${CYAN}${BOLD}Export Commands${RESET}"
  echo -e "${CYAN}─────────────────────${RESET}"
  
  # Generate default filename with timestamp
  timestamp=$(date +"%Y%m%d_%H%M%S")
  default_filename="toolbox_export_${timestamp}.json"
  
  # Ask for filename
  read -p "$(echo -e "${YELLOW}Export filename (default: $default_filename):${RESET} ")" filename
  filename="${filename:-$default_filename}"
  
  # Add json extension if not present
  [[ "$filename" != *.json ]] && filename="${filename}.json"
  
  # Select category using vim-like navigation
  category=$(select_category "Select Category to Export")
  status=$?
  
  if [ $status -ne 0 ]; then
    echo -e "${YELLOW}Export cancelled.${RESET}"
    read -n 1 -s -r -p "Press any key to continue..."
    return
  fi
  
  # Export commands
  export_commands "$filename" "$category"
  
  read -n 1 -s -r -p "Press any key to continue..."
}

# Function to import commands in TUI mode
tui_import_commands() {
  clear
  echo -e "${CYAN}${BOLD}Import Commands${RESET}"
  echo -e "${CYAN}─────────────────────${RESET}"
  
  # List available export files
  echo -e "${YELLOW}Select a file to import:${RESET}"
  
  # Find all json files in the export directory
  export_files=$(find "$EXPORT_DIR" -name "*.json" -type f 2>/dev/null | sort -r)
  
  if [ -z "$export_files" ]; then
    echo -e "${RED}No export files found in $EXPORT_DIR${RESET}"
    echo -e "${YELLOW}You can also provide a full path to a json file.${RESET}"
    read -p "$(echo -e "${YELLOW}Enter path to json file:${RESET} ")" filename
    
    if [ -z "$filename" ]; then
      echo -e "${RED}No file specified, import cancelled.${RESET}"
      read -n 1 -s -r -p "Press any key to continue..."
      return
    fi
  else
    # Show the exports list using fzf
    filename=$(echo "$export_files" | 
      fzf --height 15 --layout=reverse --border \
          --prompt="Select file to import: " \
          --header="↑/↓:Navigate | Enter:Select | ESC:Cancel" \
          --preview "jq -r '.commands | length' {} | xargs echo 'Commands in file:' ; 
                    jq -r '.commands | map(.category) | unique | .[]' {} | sort | xargs echo 'Categories:'"
    )
    
    if [ -z "$filename" ]; then
      echo -e "${YELLOW}Import cancelled.${RESET}"
      read -n 1 -s -r -p "Press any key to continue..."
      return
    fi
  fi
  
  # Import the selected file
  import_commands "$filename"
  
  read -n 1 -s -r -p "Press any key to continue..."
}

# Function to add a new command
add_command() {
  name="$1"
  command_to_run="$2"
  description="$3"
  category="$4"
  
  # Check if command already exists
  if jq -e ".commands[\"$name\"]" "$DB_FILE" > /dev/null 2>&1; then
    echo -e "${YELLOW}Command '$name' already exists. Use modify to update it.${RESET}"
    return 1
  fi
  
  # Add the command to the database
  jq --arg name "$name" \
     --arg cmd "$command_to_run" \
     --arg desc "$description" \
     --arg cat "$category" \
     '.commands[$name] = {"command": $cmd, "description": $desc, "category": $cat}' \
     "$DB_FILE" > "$DB_FILE.tmp" && mv "$DB_FILE.tmp" "$DB_FILE"
  
  echo -e "${GREEN}✓ Command '${BOLD}$name${RESET}${GREEN}' added successfully.${RESET}"
}

# Interactive command addition
interactive_add() {
  echo -e "${CYAN}${BOLD}Add a New Command${RESET}"
  echo -e "${CYAN}─────────────────────${RESET}"
  
  read -p "$(echo -e "${YELLOW}Command name:${RESET} ")" name
  if [ -z "$name" ]; then
    echo -e "${RED}Error: Command name cannot be empty.${RESET}"
    return 1
  fi
  
  # Check if command already exists
  if jq -e ".commands[\"$name\"]" "$DB_FILE" > /dev/null 2>&1; then
    echo -e "${YELLOW}Command '$name' already exists. Use modify to update it.${RESET}"
    return 1
  fi
  
  read -p "$(echo -e "${YELLOW}Command to run:${RESET} ")" command_to_run
  if [ -z "$command_to_run" ]; then
    echo -e "${RED}Error: Command to run cannot be empty.${RESET}"
    return 1
  fi
  
  read -p "$(echo -e "${YELLOW}Description (optional):${RESET} ")" description
  
  # Show available categories and let user choose
  available_categories=$(jq -r '.commands | map(.category) | unique | .[]' "$DB_FILE" 2>/dev/null)
  if [ -n "$available_categories" ]; then
    echo -e "${YELLOW}Available categories:${RESET}"
    echo "$available_categories" | nl -w2 -s') '
    echo "n) Create new category"
  fi
  
  read -p "$(echo -e "${YELLOW}Category (number, name, or 'n' for new):${RESET} ")" category_choice
  
  if [[ "$category_choice" =~ ^[0-9]+$ ]] && [ -n "$available_categories" ]; then
    # User selected a number
    category=$(echo "$available_categories" | sed -n "${category_choice}p")
    if [ -z "$category" ]; then
      category="general"
    fi
  elif [ "$category_choice" = "n" ]; then
    # User wants to create a new category
    read -p "$(echo -e "${YELLOW}New category name:${RESET} ")" category
    if [ -z "$category" ]; then
      category="general"
    fi
  elif [ -n "$category_choice" ]; then
    # User entered a category name
    category="$category_choice"
  else
    # Default category
    category="general"
  fi
  
  add_command "$name" "$command_to_run" "$description" "$category"
}

# Function to list commands
list_commands() {
  category="$1"
  search_term="$2"
  
  # Check if there are any commands
  command_count=$(jq '.commands | length' "$DB_FILE")
  if [ "$command_count" -eq 0 ]; then
    echo -e "${YELLOW}No commands found. Add some with 'toolbox add' or 'toolbox interactive'.${RESET}"
    return
  fi
  
  # Create a temporary file for filtered results
  tmp_file=$(mktemp)
  
  # Start with all commands
  jq '.commands' "$DB_FILE" > "$tmp_file"
  
  # Filter by category if specified
  if [ -n "$category" ]; then
    jq --arg cat "$category" 'with_entries(select(.value.category == $cat))' "$tmp_file" > "$tmp_file.new" 
    mv "$tmp_file.new" "$tmp_file"
  fi
  
  # Filter by search term if specified
  if [ -n "$search_term" ]; then
    jq --arg term "$search_term" 'with_entries(select(.key | contains($term) or .value.description | contains($term)))' "$tmp_file" > "$tmp_file.new"
    mv "$tmp_file.new" "$tmp_file"
  fi
  
  # Check if we have any results after filtering
  result_count=$(jq 'length' "$tmp_file")
  if [ "$result_count" -eq 0 ]; then
    echo -e "${YELLOW}No matching commands found.${RESET}"
    rm "$tmp_file"
    return
  fi
  
  # Group and display by category
  categories=$(jq -r '[.[].category] | unique | .[]' "$tmp_file" | sort)
  
  for cat in $categories; do
    # Using tr for uppercase instead of ${var^^} for better compatibility
    cat_upper=$(echo "$cat" | tr '[:lower:]' '[:upper:]')
    echo -e "\n${MAGENTA}${BOLD}== $cat_upper ==${RESET}"
    jq -r --arg cat "$cat" 'to_entries | map(select(.value.category == $cat)) | sort_by(.key) | .[] | 
      "\(.key)\t\(.value.command)\t\(.value.description)"' "$tmp_file" | 
      while IFS=$'\t' read -r cmd_name cmd_command cmd_desc; do
        echo -e "  ${CYAN}${BOLD}$cmd_name${RESET}"
        [ -n "$cmd_desc" ] && echo -e "    ${YELLOW}$cmd_desc${RESET}"
        echo -e "    ${GREEN}$ $cmd_command${RESET}"
      done
  done
  
  # Clean up
  rm "$tmp_file"
}

# Function to run a command
run_command() {
  name="$1"
  
  # Check if command exists
  if ! jq -e ".commands[\"$name\"]" "$DB_FILE" > /dev/null 2>&1; then
    echo -e "${RED}Command '$name' not found.${RESET}"
    return 1
  fi
  
  # Get the command to run
  command_to_run=$(jq -r ".commands[\"$name\"].command" "$DB_FILE")
  
  echo -e "${CYAN}Running: ${GREEN}$command_to_run${RESET}"
  echo -e "${YELLOW}─────────────────────────────────────${RESET}"
  eval "$command_to_run"
  echo -e "${YELLOW}─────────────────────────────────────${RESET}"
  echo -e "${GREEN}Command execution completed.${RESET}"
}

# Function to delete a command
delete_command() {
  name="$1"
  
  # Check if command exists
  if ! jq -e ".commands[\"$name\"]" "$DB_FILE" > /dev/null 2>&1; then
    echo -e "${RED}Command '$name' not found.${RESET}"
    return 1
  fi
  
  # Confirm deletion
  command_desc=$(jq -r ".commands[\"$name\"].description" "$DB_FILE")
  command_cmd=$(jq -r ".commands[\"$name\"].command" "$DB_FILE")
  
  echo -e "${YELLOW}About to delete:${RESET}"
  echo -e "  ${CYAN}${BOLD}$name${RESET}"
  [ -n "$command_desc" ] && echo -e "  ${YELLOW}$command_desc${RESET}"
  echo -e "  ${GREEN}$ $command_cmd${RESET}"
  
  read -p "$(echo -e "${RED}Are you sure you want to delete this command? (y/N):${RESET} ")" confirm
  if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}Deletion cancelled.${RESET}"
    return 0
  fi
  
  # Delete the command
  jq --arg name "$name" 'del(.commands[$name])' "$DB_FILE" > "$DB_FILE.tmp" && mv "$DB_FILE.tmp" "$DB_FILE"
  
  echo -e "${GREEN}✓ Command '${BOLD}$name${RESET}${GREEN}' deleted successfully.${RESET}"
}

# Function to modify a command
modify_command() {
  name="$1"
  new_command="$2"
  new_description="$3"
  new_category="$4"
  
  # Check if command exists
  if ! jq -e ".commands[\"$name\"]" "$DB_FILE" > /dev/null 2>&1; then
    echo -e "${RED}Command '$name' not found.${RESET}"
    return 1
  fi
  
  # Get current values
  current_command=$(jq -r ".commands[\"$name\"].command" "$DB_FILE")
  current_description=$(jq -r ".commands[\"$name\"].description" "$DB_FILE")
  current_category=$(jq -r ".commands[\"$name\"].category" "$DB_FILE")
  
  # Use new values or fallback to current values
  command_to_use="${new_command:-$current_command}"
  description_to_use="${new_description:-$current_description}"
  category_to_use="${new_category:-$current_category}"
  
  # Update the command
  jq --arg name "$name" \
     --arg cmd "$command_to_use" \
     --arg desc "$description_to_use" \
     --arg cat "$category_to_use" \
     '.commands[$name] = {"command": $cmd, "description": $desc, "category": $cat}' \
     "$DB_FILE" > "$DB_FILE.tmp" && mv "$DB_FILE.tmp" "$DB_FILE"
  
  echo -e "${GREEN}✓ Command '${BOLD}$name${RESET}${GREEN}' updated successfully.${RESET}"
}

# Interactive command modification
interactive_modify() {
  echo -e "${CYAN}${BOLD}Modify an Existing Command${RESET}"
  echo -e "${CYAN}─────────────────────────${RESET}"
  
  read -p "$(echo -e "${YELLOW}Command name to modify:${RESET} ")" name
  if [ -z "$name" ]; then
    echo -e "${RED}Error: Command name cannot be empty.${RESET}"
    return 1
  fi
  
  # Check if command exists
  if ! jq -e ".commands[\"$name\"]" "$DB_FILE" > /dev/null 2>&1; then
    echo -e "${RED}Command '$name' not found.${RESET}"
    return 1
  fi
  
  # Get current values
  current_command=$(jq -r ".commands[\"$name\"].command" "$DB_FILE")
  current_description=$(jq -r ".commands[\"$name\"].description" "$DB_FILE")
  current_category=$(jq -r ".commands[\"$name\"].category" "$DB_FILE")
  
  echo -e "${CYAN}Current command:${RESET} ${GREEN}$current_command${RESET}"
  read -p "$(echo -e "${YELLOW}New command (leave empty to keep current):${RESET} ")" new_command
  command_to_use="${new_command:-$current_command}"
  
  echo -e "${CYAN}Current description:${RESET} ${YELLOW}$current_description${RESET}"
  read -p "$(echo -e "${YELLOW}New description (leave empty to keep current):${RESET} ")" new_description
  description_to_use="${new_description:-$current_description}"
  
  echo -e "${CYAN}Current category:${RESET} ${MAGENTA}$current_category${RESET}"
  
  # Show available categories and let user choose
  available_categories=$(jq -r '.commands | map(.category) | unique | .[]' "$DB_FILE" 2>/dev/null)
  if [ -n "$available_categories" ]; then
    echo -e "${YELLOW}Available categories:${RESET}"
    echo "$available_categories" | nl -w2 -s') '
    echo "n) Create new category"
    echo "k) Keep current category"
  fi
  
  read -p "$(echo -e "${YELLOW}Category (number, name, 'n' for new, 'k' to keep):${RESET} ")" category_choice
  
  if [ "$category_choice" = "k" ] || [ -z "$category_choice" ]; then
    # Keep current category
    category_to_use="$current_category"
  elif [[ "$category_choice" =~ ^[0-9]+$ ]] && [ -n "$available_categories" ]; then
    # User selected a number
    category=$(echo "$available_categories" | sed -n "${category_choice}p")
    category_to_use="${category:-$current_category}"
  elif [ "$category_choice" = "n" ]; then
    # User wants to create a new category
    read -p "$(echo -e "${YELLOW}New category name:${RESET} ")" new_category
    category_to_use="${new_category:-$current_category}"
  else
    # User entered a category name
    category_to_use="$category_choice"
  fi
  
  # Update the command
  jq --arg name "$name" \
     --arg cmd "$command_to_use" \
     --arg desc "$description_to_use" \
     --arg cat "$category_to_use" \
     '.commands[$name] = {"command": $cmd, "description": $desc, "category": $cat}' \
     "$DB_FILE" > "$DB_FILE.tmp" && mv "$DB_FILE.tmp" "$DB_FILE"
  
  echo -e "${GREEN}✓ Command '${BOLD}$name${RESET}${GREEN}' updated successfully.${RESET}"
}

# Function to list categories
list_categories() {
  # Check if there are any commands
  command_count=$(jq '.commands | length' "$DB_FILE")
  if [ "$command_count" -eq 0 ]; then
    echo -e "${YELLOW}No commands found. Add some with 'toolbox add' or 'toolbox interactive'.${RESET}"
    return
  fi
  
  # Get list of categories with command counts
  echo -e "${CYAN}${BOLD}Available Categories${RESET}"
  echo -e "${CYAN}─────────────────────${RESET}"
  jq -r '.commands | map(.category) | group_by(.) | map({category: .[0], count: length}) | 
    sort_by(.category) | .[] | "\(.category) (\(.count) commands)"' "$DB_FILE" | 
    while read -r line; do
      echo -e "  ${MAGENTA}$line${RESET}"
    done
}

# Export commands to a file
export_commands() {
  filename="$1"
  category="$2"
  
  if [ -z "$filename" ]; then
    # Generate default filename with timestamp
    timestamp=$(date +"%Y%m%d_%H%M%S")
    filename="toolbox_export_${timestamp}.json"
  fi
  
  # Add json extension if not present
  [[ "$filename" != *.json ]] && filename="${filename}.json"
  
  full_path="$EXPORT_DIR/$filename"
  
  if [ -n "$category" ]; then
    # Export only specified category
    jq --arg cat "$category" '{commands: (.commands | with_entries(select(.value.category == $cat)))}' "$DB_FILE" > "$full_path"
    echo -e "${GREEN}✓ Commands in category '${BOLD}$category${RESET}${GREEN}' exported to ${BOLD}$full_path${RESET}"
  else
    # Export all commands
    cp "$DB_FILE" "$full_path"
    echo -e "${GREEN}✓ All commands exported to ${BOLD}$full_path${RESET}"
  fi
}

# Import commands from a file
import_commands() {
  filename="$1"
  
  if [ ! -f "$filename" ]; then
    # Check if file exists in exports directory
    if [ -f "$EXPORT_DIR/$filename" ]; then
      filename="$EXPORT_DIR/$filename"
    else
      echo -e "${RED}File not found: $filename${RESET}"
      return 1
    fi
  fi
  
  # Validate JSON format
  if ! jq . "$filename" > /dev/null 2>&1; then
    echo -e "${RED}Invalid JSON file: $filename${RESET}"
    return 1
  fi
  
  # Get count of commands to import
  import_count=$(jq '.commands | length' "$filename")
  
  if [ "$import_count" -eq 0 ]; then
    echo -e "${YELLOW}No commands found in the import file.${RESET}"
    return 0
  fi
  
  echo -e "${YELLOW}About to import ${BOLD}$import_count${RESET}${YELLOW} commands.${RESET}"
  read -p "$(echo -e "${YELLOW}Do you want to continue? (Y/n):${RESET} ")" confirm
  if [[ "$confirm" =~ ^[Nn]$ ]]; then
    echo -e "${YELLOW}Import cancelled.${RESET}"
    return 0
  fi
  
  # Merge the commands
  jq -s '.[0].commands = (.[0].commands + .[1].commands) | .[0]' "$DB_FILE" "$filename" > "$DB_FILE.tmp" && mv "$DB_FILE.tmp" "$DB_FILE"
  
  echo -e "${GREEN}✓ Imported ${BOLD}$import_count${RESET}${GREEN} commands successfully.${RESET}"
}

# Function to show usage information
show_usage() {
  show_logo
  echo -e "${BOLD}${CYAN}Usage:${RESET} toolbox COMMAND [ARGS]"
  echo
  echo -e "${BOLD}${CYAN}Commands:${RESET}"
  echo -e "  ${YELLOW}tui${RESET}                      Start full-screen terminal user interface"
  echo -e "  ${YELLOW}add${RESET} NAME COMMAND [-d DESCRIPTION] [-c CATEGORY]"
  echo -e "                           Add a new command shortcut"
  echo -e "  ${YELLOW}interactive${RESET}                Interactive mode for adding/modifying commands"
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
  echo -e "  toolbox tui"
  echo -e "  toolbox add list-ports \"lsof -i -P -n | grep LISTEN\" -d \"List all listening ports\" -c \"network\""
  echo -e "  toolbox interactive"
  echo -e "  toolbox list"
  echo -e "  toolbox list -c network"
  echo -e "  toolbox run list-ports"
  echo -e "  toolbox export my_commands -c system"
  echo -e "  toolbox import my_commands.json"
}

# Main function to handle command-line arguments
main() {
  check_dependencies
  
  cmd="$1"
  shift || true
  
  case "$cmd" in
    tui)
      run_tui_mode
      ;;
    
    add)
      if [ $# -lt 2 ]; then
        echo -e "${RED}Error: 'add' requires NAME and COMMAND arguments.${RESET}"
        show_usage
        exit 1
      fi
      
      name="$1"
      command_to_run="$2"
      shift 2
      
      description=""
      category="general"
      
      # Parse optional arguments
      while [ $# -gt 0 ]; do
        case "$1" in
          -d|--description)
            description="$2"
            shift 2
            ;;
          -c|--category)
            category="$2"
            shift 2
            ;;
          *)
            echo -e "${RED}Unknown option: $1${RESET}"
            show_usage
            exit 1
            ;;
        esac
      done
      
      add_command "$name" "$command_to_run" "$description" "$category"
      ;;
    
    interactive)
      if [ "$1" = "modify" ]; then
        interactive_modify
      else
        interactive_add
      fi
      ;;
    
    list)
      category=""
      search_term=""
      
      # Parse optional arguments
      while [ $# -gt 0 ]; do
        case "$1" in
          -c|--category)
            category="$2"
            shift 2
            ;;
          -s|--search)
            search_term="$2"
            shift 2
            ;;
          *)
            echo -e "${RED}Unknown option: $1${RESET}"
            show_usage
            exit 1
            ;;
        esac
      done
      
      list_commands "$category" "$search_term"
      ;;
    
    run)
      if [ $# -lt 1 ]; then
        echo -e "${RED}Error: 'run' requires NAME argument.${RESET}"
        show_usage
        exit 1
      fi
      
      run_command "$1"
      ;;
    
    delete)
      if [ $# -lt 1 ]; then
        echo -e "${RED}Error: 'delete' requires NAME argument.${RESET}"
        show_usage
        exit 1
      fi
      
      delete_command "$1"
      ;;
    
    modify)
      if [ $# -lt 1 ]; then
        echo -e "${RED}Error: 'modify' requires NAME argument.${RESET}"
        show_usage
        exit 1
      fi
      
      name="$1"
      shift
      
      # If no additional arguments, go to interactive mode
      if [ $# -eq 0 ]; then
        # Call interactive modify with the command name
        name_temp="$name"
        interactive_modify "$name_temp"
        return
      fi
      
      new_command=""
      new_description=""
      new_category=""
      
      # Parse optional arguments
      while [ $# -gt 0 ]; do
        case "$1" in
          -cmd|--command)
            new_command="$2"
            shift 2
            ;;
          -d|--description)
            new_description="$2"
            shift 2
            ;;
          -c|--category)
            new_category="$2"
            shift 2
            ;;
          *)
            echo -e "${RED}Unknown option: $1${RESET}"
            show_usage
            exit 1
            ;;
        esac
      done
      
      modify_command "$name" "$new_command" "$new_description" "$new_category"
      ;;
    
    categories)
      list_categories
      ;;
    
    export)
      filename="$1"
      category=""
      
      shift || true
      
      # Parse optional arguments
      while [ $# -gt 0 ]; do
        case "$1" in
          -c|--category)
            category="$2"
            shift 2
            ;;
          *)
            echo -e "${RED}Unknown option: $1${RESET}"
            show_usage
            exit 1
            ;;
        esac
      done
      
      export_commands "$filename" "$category"
      ;;
    
    import)
      if [ $# -lt 1 ]; then
        echo -e "${RED}Error: 'import' requires FILENAME argument.${RESET}"
        show_usage
        exit 1
      fi
      
      import_commands "$1"
      ;;
    
    help|--help|-h)
      show_usage
      ;;
    
    *)
      if [ -z "$cmd" ]; then
        show_usage
      else
        echo -e "${RED}Error: Unknown command '$cmd'.${RESET}"
        show_usage
        exit 1
      fi
      ;;
  esac
}

# Run the main function with all arguments
main "$@"