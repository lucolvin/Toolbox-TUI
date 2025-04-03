#!/bin/bash

# Function to search and run commands
search_and_run_commands() {
  # Check if there are any commands
  command_count=$(jq '.commands | length' "$DB_FILE")
  if [ "$command_count" -eq 0 ]; then
    gum style --foreground "#ffcc00" "No commands found. Add some first."
    read -n 1 -s -r -p "Press any key to continue..."
    return
  fi
  
  # Create a temporary file that combines command name and details for better display
  tmp_file=$(mktemp)
  jq -r '.commands | to_entries[] | "\(.key)|\(.value.category)|\(.value.description)|\(.value.command)"' "$DB_FILE" > "$tmp_file"
  
  # Clear screen and show header
  clear
  echo -e "$(gum style --foreground "#36a3ff" --bold "Search Commands")"
  echo -e "$(gum style --foreground "#cccccc" "Type to search for commands")"
  
  # Use gum filter for command selection WITH searching
  local selection
  selection=$(cat "$tmp_file" | 
    gum filter --placeholder="Search by name or description..." \
    --indicator="→" \
    --indicator.foreground="#00cc66" \
    --match.foreground="#00cc66" \
    --no-match-text="No matching commands" \
    --header="$(gum style --foreground "#36a3ff" "Type to search, ESC to cancel")")
  
  # Clean up
  rm "$tmp_file"
  
  # If no selection, return
  if [ -z "$selection" ]; then
    return
  fi
  
  # Extract command name from selection - use proper delimiter
  local cmd_name=$(echo "$selection" | cut -d'|' -f1)
  
  # Get command details using proper quoting
  local command_to_run=$(jq -r --arg name "$cmd_name" '.commands[$name].command' "$DB_FILE")
  local cmd_description=$(jq -r --arg name "$cmd_name" '.commands[$name].description' "$DB_FILE")
  local cmd_category=$(jq -r --arg name "$cmd_name" '.commands[$name].category' "$DB_FILE")
  
  # Ask for confirmation before running
  clear
  echo -e "$(gum style --border normal --border-foreground "#36a3ff" --padding "1 2" --width 80 --align left \
    "$(gum style --foreground "#36a3ff" --bold "Command Details")\n\n\
    $(gum style --foreground "#ffffff" --bold "Name:") $(gum style --foreground "#00cc66" "$cmd_name")\n\
    $([ -n "$cmd_description" ] && echo -e "$(gum style --foreground "#ffffff" --bold "Description:") $(gum style --foreground "#ffcc00" "$cmd_description")\n")\
    $(gum style --foreground "#ffffff" --bold "Category:") $(gum style --foreground "#cc66ff" "$cmd_category")\n\
    $(gum style --foreground "#ffffff" --bold "Command:") $(gum style --foreground "#00cc99" "$command_to_run")")"
  
  # Use gum confirm for confirmation
  if gum confirm "Do you want to run this command?"; then
    # Show cursor while running command
    show_cursor
    
    # Clear screen for command output
    clear
    echo -e "$(gum style --foreground "#36a3ff" --bold "Running Command:")"
    echo -e "$(gum style --foreground "#00cc99" "$command_to_run")"
    echo -e "$(gum style --foreground "#ffcc00" "─────────────────────────────────────")"
    eval "$command_to_run"
    echo -e "$(gum style --foreground "#ffcc00" "─────────────────────────────────────")"
    echo -e "$(gum style --foreground "#00cc66" --bold "✓ Command execution completed")"
    echo
    read -n 1 -s -r -p "Press any key to continue..."
    
    # Hide cursor when returning to TUI
    hide_cursor
  fi
}
