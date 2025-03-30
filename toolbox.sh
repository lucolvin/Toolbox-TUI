#!/bin/bash

# Toolbox - A terminal tool for managing command shortcuts
# Usage: toolbox command [arguments]

# Configuration
CONFIG_DIR="$HOME/.toolbox"
DB_FILE="$CONFIG_DIR/commands.json"

# Ensure the toolbox directory exists
mkdir -p "$CONFIG_DIR"

# Initialize the database file if it doesn't exist
if [ ! -f "$DB_FILE" ]; then
  echo '{"commands":{}}' > "$DB_FILE"
fi

# Function to check if jq is installed
check_dependencies() {
  if ! command -v jq &> /dev/null; then
    echo "Error: jq is required but not installed."
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
    echo "Command '$name' already exists. Use modify to update it."
    return 1
  fi
  
  # Add the command to the database
  jq --arg name "$name" \
     --arg cmd "$command_to_run" \
     --arg desc "$description" \
     --arg cat "$category" \
     '.commands[$name] = {"command": $cmd, "description": $desc, "category": $cat}' \
     "$DB_FILE" > "$DB_FILE.tmp" && mv "$DB_FILE.tmp" "$DB_FILE"
  
  echo "Command '$name' added successfully."
}

# Function to list commands
list_commands() {
  category="$1"
  search_term="$2"
  
  # Check if there are any commands
  command_count=$(jq '.commands | length' "$DB_FILE")
  if [ "$command_count" -eq 0 ]; then
    echo "No commands found. Add some with 'toolbox add'."
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
    echo "No matching commands found."
    rm "$tmp_file"
    return
  fi
  
  # Group and display by category
  categories=$(jq -r '[.[].category] | unique | .[]' "$tmp_file" | sort)
  
  for cat in $categories; do
    # Using tr for uppercase instead of ${var^^} for better compatibility
    cat_upper=$(echo "$cat" | tr '[:lower:]' '[:upper:]')
    echo -e "\n== $cat_upper =="
    jq -r --arg cat "$cat" 'to_entries | map(select(.value.category == $cat)) | sort_by(.key) | .[] | 
      "\(.key)\t\(.value.command)\t\(.value.description)"' "$tmp_file" | 
      while IFS=$'\t' read -r cmd_name cmd_command cmd_desc; do
        printf "  %-20s - %s\n" "$cmd_name" "$cmd_desc"
        echo "    $ $cmd_command"
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
    echo "Command '$name' not found."
    return 1
  fi
  
  # Get the command to run
  command_to_run=$(jq -r ".commands[\"$name\"].command" "$DB_FILE")
  
  echo "Running: $command_to_run"
  eval "$command_to_run"
}

# Function to delete a command
delete_command() {
  name="$1"
  
  # Check if command exists
  if ! jq -e ".commands[\"$name\"]" "$DB_FILE" > /dev/null 2>&1; then
    echo "Command '$name' not found."
    return 1
  fi
  
  # Delete the command
  jq --arg name "$name" 'del(.commands[$name])' "$DB_FILE" > "$DB_FILE.tmp" && mv "$DB_FILE.tmp" "$DB_FILE"
  
  echo "Command '$name' deleted successfully."
}

# Function to modify a command
modify_command() {
  name="$1"
  new_command="$2"
  new_description="$3"
  new_category="$4"
  
  # Check if command exists
  if ! jq -e ".commands[\"$name\"]" "$DB_FILE" > /dev/null 2>&1; then
    echo "Command '$name' not found."
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
  
  echo "Command '$name' updated successfully."
}

# Function to list categories
list_categories() {
  # Check if there are any commands
  command_count=$(jq '.commands | length' "$DB_FILE")
  if [ "$command_count" -eq 0 ]; then
    echo "No commands found. Add some with 'toolbox add'."
    return
  fi
  
  # Get list of categories with command counts
  echo "Available categories:"
  jq -r '.commands | map(.category) | group_by(.) | map({category: .[0], count: length}) | 
    sort_by(.category) | .[] | "\(.category) (\(.count) commands)"' "$DB_FILE" | 
    while read -r line; do
      echo "  $line"
    done
}

# Function to show usage information
show_usage() {
  cat <<EOF
Toolbox - Manage useful command shortcuts

Usage: toolbox COMMAND [ARGS]

Commands:
  add NAME COMMAND [-d DESCRIPTION] [-c CATEGORY]
                           Add a new command shortcut
  list [-c CATEGORY] [-s SEARCH]
                           List saved commands
  run NAME                 Run a saved command
  delete NAME              Delete a command
  modify NAME [-cmd COMMAND] [-d DESCRIPTION] [-c CATEGORY]
                           Modify an existing command
  categories               List all available categories
  help                     Show this help message

Examples:
  toolbox add list-ports "lsof -i -P -n | grep LISTEN" -d "List all listening ports" -c "network"
  toolbox list
  toolbox list -c network
  toolbox run list-ports
  toolbox modify list-ports -d "Show all listening ports" -c "system"
EOF
}

# Main function to handle command-line arguments
main() {
  check_dependencies
  
  cmd="$1"
  shift || true
  
  case "$cmd" in
    add)
      if [ $# -lt 2 ]; then
        echo "Error: 'add' requires NAME and COMMAND arguments."
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
            echo "Unknown option: $1"
            show_usage
            exit 1
            ;;
        esac
      done
      
      add_command "$name" "$command_to_run" "$description" "$category"
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
            echo "Unknown option: $1"
            show_usage
            exit 1
            ;;
        esac
      done
      
      list_commands "$category" "$search_term"
      ;;
    
    run)
      if [ $# -lt 1 ]; then
        echo "Error: 'run' requires NAME argument."
        show_usage
        exit 1
      fi
      
      run_command "$1"
      ;;
    
    delete)
      if [ $# -lt 1 ]; then
        echo "Error: 'delete' requires NAME argument."
        show_usage
        exit 1
      fi
      
      delete_command "$1"
      ;;
    
    modify)
      if [ $# -lt 1 ]; then
        echo "Error: 'modify' requires NAME argument."
        show_usage
        exit 1
      fi
      
      name="$1"
      shift
      
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
            echo "Unknown option: $1"
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
    
    help|--help|-h)
      show_usage
      ;;
    
    *)
      echo "Error: Unknown command '$cmd'."
      show_usage
      exit 1
      ;;
  esac
}

# Run the main function with all arguments
main "$@"