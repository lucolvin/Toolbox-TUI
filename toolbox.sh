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