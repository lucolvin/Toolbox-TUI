#!/bin/bash

# Function to export commands in TUI mode
tui_export_commands() {
  clear
  echo -e "${CYAN}${BOLD}Export Commands${RESET}"
  echo -e "${CYAN}─────────────────────${RESET}"
  
  # Generate default filename with timestamp
  timestamp=$(date +"%Y%m%d_%H%M%S")
  default_filename="toolbox_export_${timestamp}.json"
  
  # Show cursor for input
  show_cursor
  
  # Ask for filename using gum
  filename=$(gum input --placeholder="$default_filename" --header="Export filename" --value="$default_filename")
  filename="${filename:-$default_filename}"
  
  # Add json extension if not present
  [[ "$filename" != *.json ]] && filename="${filename}.json"
  
  # Hide cursor for menu
  hide_cursor
  
  # Select category using gum
  category=$(select_category "Select Category to Export")
  status=$?
  
  if [ $status -ne 0 ]; then
    echo -e "${YELLOW}Export cancelled.${RESET}"
    read -n 1 -s -r -p "Press any key to continue..."
    return
  fi
  
  export_commands "$filename" "$category"
  read -n 1 -s -r -p "Press any key to continue..."
}

# Function to import commands in TUI mode
tui_import_commands() {
  clear
  echo -e "${CYAN}${BOLD}Import Commands${RESET}"
  echo -e "${CYAN}─────────────────────${RESET}"
  
  # List files in the export directory
  files=$(find "$EXPORT_DIR" -type f -name "*.json" -exec basename {} \; | sort)
  
  if [ -z "$files" ]; then
    echo -e "${YELLOW}No exported files found in $EXPORT_DIR${RESET}"
    read -n 1 -s -r -p "Press any key to continue..."
    return
  fi
  
  # Use gum choose for file selection
  filename=$(echo "$files" | gum choose --header="Select file to import")
  
  if [ -z "$filename" ]; then
    echo -e "${YELLOW}Import cancelled.${RESET}"
    read -n 1 -s -r -p "Press any key to continue..."
    return
  fi
  
  # Import the selected file
  import_commands "$EXPORT_DIR/$filename"
  
  read -n 1 -s -r -p "Press any key to continue..."
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
