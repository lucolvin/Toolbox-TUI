#!/bin/bash

# Full screen terminal UI mode
run_tui_mode() {
  # Hide cursor when entering TUI mode
  hide_cursor
  
  # Setup trap to restore cursor on exit
  trap show_cursor EXIT INT TERM
  
  # First check if gum is installed (needed for TUI interface)
  if ! check_gum; then
    echo -e "${YELLOW}Gum is required for TUI mode.${RESET}"
    echo -e "${YELLOW}Cannot continue without Gum installed.${RESET}"
    sleep 2
    show_cursor
    return
  fi
  
  # Clear screen and show header
  clear
  
  # Use gum style for a more modern header
  echo -e "$(gum style --border normal --margin "1" --padding "1 2" --border-foreground "#36a3ff" "Welcome to Toolbox - Command Shortcut Manager")"
  
  # Menu options
  local options=(
    "🏃 View & Run Commands"
    "🔍 Search Commands"
    "➕ Add New Command"
    "✏️  Modify Command"
    "🗑️  Delete Command"
    "📤 Export Commands"
    "📥 Import Commands"
    "🚪 Quit"
  )
  
  # Use gum choose for menu selection with more styling
  local selection=$(printf "%s\n" "${options[@]}" | 
    gum choose --header="$(gum style --foreground "#36a3ff" "Select an option:")" \
    --cursor.foreground="#00FF00" \
    --height=15 \
    --cursor="▶ " \
    --selected-prefix="✓ " \
    --unselected-prefix="  ")
  
  # Handle menu selection
  if [ -z "$selection" ]; then
    # User cancelled
    echo -e "${GREEN}Exiting TUI mode.${RESET}"
    show_cursor
    return
  else
    case "$selection" in
      "🏃 View & Run Commands") tui_browse_categories ;;
      "🔍 Search Commands") search_and_run_commands ;;
      "➕ Add New Command") tui_add_command ;;
      "✏️  Modify Command") tui_modify_command ;;
      "🗑️  Delete Command") tui_delete_command ;;
      "📤 Export Commands") tui_export_commands ;;
      "📥 Import Commands") tui_import_commands ;;
      "🚪 Quit") echo -e "${GREEN}Exiting TUI mode.${RESET}"; show_cursor; return ;;
    esac
  fi
  
  # Return to TUI mode after an action completes (recursive)
  run_tui_mode
}

# New function to browse commands by category
tui_browse_categories() {
  # Check if there are any commands
  command_count=$(jq '.commands | length' "$DB_FILE")
  if [ "$command_count" -eq 0 ]; then
    gum style --foreground "#ffcc00" "No commands found. Add some first."
    read -n 1 -s -r -p "Press any key to continue..."
    return
  fi
  
  # Get all categories
  categories=$(jq -r '.commands | map(.category) | unique | .[]' "$DB_FILE" | sort)
  
  # If we have no categories, use "general" as default
  if [ -z "$categories" ]; then
    categories="general"
  fi
  
  # Add "All Commands" as the first option
  categories=$(echo -e "All Commands\n$categories")
  
  # Show category selection with gum
  clear
  echo -e "$(gum style --foreground "#36a3ff" --bold "Command Categories")"
  echo -e "$(gum style --foreground "#cccccc" "Select a category to view commands")"
  
  # Present categories as a simple list without any formatting
  local display_categories=""
  while IFS= read -r category; do
    display_categories="${display_categories}${category}\n"
  done <<< "$categories"
  
  # Let user select a category with simple gum choose
  selected_category=$(echo -e "$display_categories" | gum choose --height=10)
  
  # If no selection, return
  if [ -z "$selected_category" ]; then
    return
  fi
  
  # Show commands in the selected category
  tui_view_commands_in_category "$selected_category"
}

# Function to view commands in a specific category
tui_view_commands_in_category() {
  local category="$1"
  
  # Clear screen and show header
  clear
  
  if [ "$category" = "All Commands" ]; then
    echo -e "$(gum style --foreground "#36a3ff" --bold "All Commands")"
    # Get all commands
    cmd_file=$(mktemp)
    jq -r '.commands | to_entries[] | "\(.key)|\(.value.category)|\(.value.description)|\(.value.command)"' "$DB_FILE" > "$cmd_file"
  else
    echo -e "$(gum style --foreground "#36a3ff" --bold "Commands in category: $category")"
    # Get commands in the selected category - ensure exact category match
    cmd_file=$(mktemp)
    jq -r --arg cat "$category" '.commands | to_entries[] | select(.value.category == $cat) | "\(.key)|\(.value.category)|\(.value.description)|\(.value.command)"' "$DB_FILE" > "$cmd_file"
  fi
  
  # If no commands in category or empty file
  if [ ! -s "$cmd_file" ]; then
    gum style --foreground "#ffcc00" "No commands found in category '$category'."
    read -n 1 -s -r -p "Press any key to continue..."
    rm "$cmd_file" 2>/dev/null
    return
  fi
  
  # Store commands in associative arrays for easier lookup
  declare -a display_items=()
  declare -a command_names=()
  declare -a command_descriptions=()
  declare -a command_categories=()
  declare -a command_actions=()
  
  # Read the file line by line and populate arrays
  while IFS='|' read -r name cat desc cmd; do
    [ -z "$name" ] && continue
    
    # Store the command data in arrays
    command_names+=("$name")
    command_categories+=("$cat")
    command_descriptions+=("$desc")
    command_actions+=("$cmd")
    
    # Create display item
    if [ -n "$desc" ]; then
      display_items+=("$name - $desc")
    else
      display_items+=("$name")
    fi
  done < "$cmd_file"
  
  # Clean up the temp file
  rm "$cmd_file" 2>/dev/null
  
  # If no commands were parsed
  if [ ${#command_names[@]} -eq 0 ]; then
    gum style --foreground "#ffcc00" "No commands found in category '$category'."
    read -n 1 -s -r -p "Press any key to continue..."
    return
  fi
  
  # Format display items for gum choose
  local display_list=$(printf "%s\n" "${display_items[@]}")
  
  # Display commands and let user select one
  echo -e "$(gum style --foreground "#cccccc" "Select a command to run:")"
  local selected_idx
  local selection=$(echo "$display_list" | gum choose --height=15)
  
  # If no selection, return
  if [ -z "$selection" ]; then
    return
  fi
  
  # Find the index of the selected item
  for i in "${!display_items[@]}"; do
    if [ "${display_items[$i]}" = "$selection" ]; then
      selected_idx=$i
      break
    fi
  done
  
  # If we couldn't find the index, return
  if [ -z "$selected_idx" ]; then
    gum style --foreground "#ff0000" "Error: couldn't identify selected command."
    read -n 1 -s -r -p "Press any key to continue..."
    return
  fi
  
  # Get the command details from our arrays
  local cmd_name="${command_names[$selected_idx]}"
  local cmd_category="${command_categories[$selected_idx]}"
  local cmd_description="${command_descriptions[$selected_idx]}"
  local command_to_run="${command_actions[$selected_idx]}"
  
  # Verify we have a valid command name
  if [ -z "$cmd_name" ] || [ -z "$command_to_run" ]; then
    gum style --foreground "#ff0000" "Error: Selected command data is incomplete."
    read -n 1 -s -r -p "Press any key to continue..."
    return
  fi
  
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
    
    # Execute the command
    eval "$command_to_run"
    
    echo -e "$(gum style --foreground "#ffcc00" "─────────────────────────────────────")"
    echo -e "$(gum style --foreground "#00cc66" --bold "✓ Command execution completed")"
    echo
    read -n 1 -s -r -p "Press any key to continue..."
    
    # Hide cursor when returning to TUI
    hide_cursor
  fi
}

# Function to view commands using gum filter instead of fzf
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
  
  # Use gum filter to select a command
  clear
  echo -e "${CYAN}${BOLD}Select a command to run:${RESET}"
  
  local selection
  selection=$(cat "$tmp_file" | gum filter --placeholder="Search commands..." --header="Select a command to run (ESC to cancel)")
  
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
  local cmd_category=$(echo "$selection" | cut -d'|' -f2)
  local cmd_description=$(echo "$selection" | cut -d'|' -f3)
  
  # Get the command to run
  local command_to_run=$(jq -r ".commands[\"$cmd_name\"].command" "$DB_FILE")
  
  # Ask for confirmation before running
  clear
  echo -e "${CYAN}Command:${RESET} ${BOLD}$cmd_name${RESET}"
  [ -n "$cmd_description" ] && echo -e "${CYAN}Description:${RESET} ${YELLOW}$cmd_description${RESET}"
  echo -e "${CYAN}Category:${RESET} ${MAGENTA}$cmd_category${RESET}"
  echo -e "${CYAN}Command to run:${RESET} ${GREEN}$command_to_run${RESET}"
  echo
  
  # Use gum confirm instead of custom confirmation
  if gum confirm "Do you want to run this command?"; then
    # Show cursor while running command
    show_cursor
    
    # Clear screen for command output
    clear
    echo -e "${CYAN}Running: ${GREEN}$command_to_run${RESET}"
    echo -e "${YELLOW}─────────────────────────────────────${RESET}"
    eval "$command_to_run"
    echo -e "${YELLOW}─────────────────────────────────────${RESET}"
    echo -e "${GREEN}Command execution completed.${RESET}"
    echo
    read -n 1 -s -r -p "Press any key to continue..."
    
    # Hide cursor when returning to TUI
    hide_cursor
  fi
}

# Function for category selection with gum
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
  
  # Create list of options
  local options=""
  
  if [ "$include_all" = "true" ]; then
    options="All Categories"
  fi
  
  # Add each category as an option
  while IFS= read -r category; do
    options="$options\n$category"
  done <<< "$available_categories"
  
  if [ "$include_new" = "true" ]; then
    options="$options\n[New Category]"
  fi
  
  # Use gum choose for category selection
  local selected_category
  selected_category=$(echo -e "$options" | gum choose --header="$title")
  
  if [ -z "$selected_category" ]; then
    # User cancelled
    return 1
  fi
  
  if [ "$selected_category" = "All Categories" ]; then
    # All Categories selected
    echo ""
    return 0
  elif [ "$selected_category" = "[New Category]" ]; then
    # New Category selected
    show_cursor
    new_category=$(gum input --placeholder="Enter new category name" --header="New Category")
    hide_cursor
    
    # Ensure new category is not empty and properly trimmed
    new_category=$(echo "$new_category" | xargs)
    if [ -z "$new_category" ]; then
      new_category="general"
    fi
    
    # Log for debugging
    echo -e "${GREEN}✓ Using new category: ${BOLD}$new_category${RESET}"
    echo "$new_category"
    return 0
  else
    # Regular category selected
    echo "$selected_category"
    return 0
  fi
}

# Function to add a command in TUI mode
tui_add_command() {
  clear
  echo -e "${CYAN}${BOLD}Add a New Command${RESET}"
  echo -e "${CYAN}─────────────────────${RESET}"
  
  # Show cursor for input
  show_cursor
  
  # Command name (required)
  name=$(gum input --placeholder="Command name" --header="Enter a name for the command")
  if [ -z "$name" ]; then
    echo -e "${RED}Error: Command name cannot be empty.${RESET}"
    read -n 1 -s -r -p "Press any key to continue..."
    hide_cursor
    return
  fi
  
  # Check if command already exists
  if jq -e ".commands[\"$name\"]" "$DB_FILE" > /dev/null 2>&1; then
    echo -e "${YELLOW}Command '$name' already exists. Use modify to update it.${RESET}"
    read -n 1 -s -r -p "Press any key to continue..."
    hide_cursor
    return
  fi
  
  # Command to run (required)
  command_to_run=$(gum input --placeholder="Command to run" --header="Enter the command to execute" --width 80)
  if [ -z "$command_to_run" ]; then
    echo -e "${RED}Error: Command to run cannot be empty.${RESET}"
    read -n 1 -s -r -p "Press any key to continue..."
    hide_cursor
    return
  fi
  
  # Description (optional)
  description=$(gum input --placeholder="Description (optional)" --header="Enter a description for the command" --width 80)
  
  # Hide cursor for menu navigation
  hide_cursor
  
  # Select category using gum
  category=$(select_category "Select Category for Command" false true)
  status=$?
  
  if [ $status -ne 0 ]; then
    echo -e "${YELLOW}Command addition cancelled.${RESET}"
    read -n 1 -s -r -p "Press any key to continue..."
    return
  fi
  
  # Ensure category is valid
  if [ -z "$category" ]; then
    category="general"
    echo -e "${YELLOW}Warning: Empty category, using 'general' instead.${RESET}"
  fi
  
  # For debugging
  echo -e "${CYAN}Debug: Category selected: '${category}'${RESET}"
  
  # Add the command with explicit parameters to avoid issues
  # Make sure the variables are properly quoted
  add_command "$name" "$command_to_run" "$description" "$category"
  
  # Show success message
  echo -e "${GREEN}✓ Command '${BOLD}$name${RESET}${GREEN}' added to category '${BOLD}$category${RESET}${GREEN}'.${RESET}"
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
  
  # Create a list of command options
  cmd_list=$(jq -r '.commands | to_entries[] | "\(.key) [\(.value.category)] - \(.value.description)"' "$DB_FILE")
  
  # Use gum filter to select a command
  clear
  echo -e "${CYAN}${BOLD}Modify a Command${RESET}"
  echo -e "${CYAN}─────────────────────${RESET}"
  
  local selection
  selection=$(echo "$cmd_list" | gum filter --placeholder="Search commands..." --header="Select a command to modify (ESC to cancel)")
  
  # If no selection, return
  if [ -z "$selection" ]; then
    return
  fi
  
  # Extract command name from selection
  local name=$(echo "$selection" | awk '{print $1}')
  
  # Get current values
  local current_command=$(jq -r ".commands[\"$name\"].command" "$DB_FILE")
  local current_description=$(jq -r ".commands[\"$name\"].description" "$DB_FILE")
  local current_category=$(jq -r ".commands[\"$name\"].category" "$DB_FILE")
  
  clear
  echo -e "${CYAN}${BOLD}Modifying Command: ${RESET}${GREEN}$name${RESET}"
  echo -e "${CYAN}─────────────────────────${RESET}"
  
  # Show cursor for input
  show_cursor
  
  # Show current command and ask for new one
  echo -e "${CYAN}Current command:${RESET} ${GREEN}$current_command${RESET}"
  new_command=$(gum input --placeholder="$current_command" --header="New command (leave empty to keep current)" --width 80 --value="$current_command")
  local command_to_use="${new_command:-$current_command}"
  
  # Show current description and ask for new one
  echo -e "${CYAN}Current description:${RESET} ${YELLOW}$current_description${RESET}"
  new_description=$(gum input --placeholder="$current_description" --header="New description (leave empty to keep current)" --width 80 --value="$current_description")
  local description_to_use="${new_description:-$current_description}"
  
  # Show current category and available categories
  echo -e "${CYAN}Current category:${RESET} ${MAGENTA}$current_category${RESET}"
  
  # Hide cursor for menu navigation
  hide_cursor
  
  # Select category using gum
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
  
  # Create a list of command options with formatting for better display
  clear
  echo -e "$(gum style --foreground "#ff3300" --bold "Delete Commands")"
  echo -e "$(gum style --foreground "#cccccc" "Select one or more commands to delete")"
  
  # Get the command names and format them for display
  cmd_file=$(mktemp)
  # Use a tab separator (since jq output is tab-safe)
  jq -r '.commands | to_entries[] | "\(.key)\t\(.value.category)\t\(.value.description)"' "$DB_FILE" > "$cmd_file"
  
  # Setup arrays for display and command name lookups
  display_items=()
  command_names=()
  
  # Format the command list for selection
  while IFS=$'\t' read -r name cat desc; do
    [ -z "$name" ] && continue
    formatted_line="$name [$cat]"
    [ -n "$desc" ] && formatted_line="$formatted_line - $desc"
    
    # Add to our arrays
    display_items+=("$formatted_line")
    command_names+=("$name")
  done < "$cmd_file"
  
  rm "$cmd_file"
  
  if [ ${#display_items[@]} -eq 0 ]; then
    echo -e "${YELLOW}No commands found to delete.${RESET}"
    read -n 1 -s -r -p "Press any key to continue..."
    return
  fi
  
  # Convert arrays to newline-separated strings for gum
  display_list=$(printf "%s\n" "${display_items[@]}")
  
  # Use gum choose for multiselect
  selected_indices=()
  selected_displays=$(echo -e "$display_list" | 
    gum choose --no-limit \
    --header="$(gum style --foreground "#ff3300" "Select commands to delete (space to select, enter when done):")" \
    --cursor.foreground="#ff3300" \
    --selected.foreground="#ff3300" \
    --cursor="▶ " \
    --selected-prefix="✓ " \
    --unselected-prefix="  ")
  
  # If no selection, return
  if [ -z "$selected_displays" ]; then
    return
  fi
  
  # Find which commands were selected by matching display strings
  selected_cmd_names=()
  while IFS= read -r selected_display; do
    [ -z "$selected_display" ] && continue
    for i in "${!display_items[@]}"; do
      if [ "${display_items[$i]}" = "$selected_display" ]; then
        selected_cmd_names+=("${command_names[$i]}")
        break
      fi
    done
  done <<< "$selected_displays"
  
  # Count selected commands
  selected_count=${#selected_cmd_names[@]}
  
  # If no valid commands were found, return
  if [ $selected_count -eq 0 ]; then
    echo -e "${YELLOW}No valid commands selected.${RESET}"
    read -n 1 -s -r -p "Press any key to continue..."
    return
  fi
  
  # Confirm deletion
  clear
  echo -e "$(gum style --border normal --border-foreground "#ff3300" --padding "1 2" --width 80 --align left \
    "$(gum style --foreground "#ff3300" --bold "Confirm Deletion")\n\n\
    $(gum style --foreground "#ffcc00" "You are about to delete $selected_count command(s):")")"
  
  # List all commands to be deleted
  for cmd_name in "${selected_cmd_names[@]}"; do
    cmd_desc=$(jq -r --arg name "$cmd_name" '.commands[$name].description' "$DB_FILE")
    cmd_command=$(jq -r --arg name "$cmd_name" '.commands[$name].command' "$DB_FILE")
    cmd_cat=$(jq -r --arg name "$cmd_name" '.commands[$name].category' "$DB_FILE")
    
    echo -e "$(gum style --foreground "#ff3300" "• $cmd_name") [$(gum style --foreground "#cc66ff" "$cmd_cat")]"
    [ -n "$cmd_desc" ] && echo -e "  $(gum style --foreground "#ffcc00" "$cmd_desc")"
    echo -e "  $(gum style --foreground "#00cc99" "$ $cmd_command")"
    echo
  done
  
  # Use gum confirm for final confirmation
  if gum confirm "$(gum style --foreground "#ff3300" "Are you SURE you want to delete these commands?")"; then
    # Delete all selected commands
    for cmd_name in "${selected_cmd_names[@]}"; do
      jq --arg name "$cmd_name" 'del(.commands[$name])' "$DB_FILE" > "$DB_FILE.tmp" && mv "$DB_FILE.tmp" "$DB_FILE"
    done
    
    if [ $selected_count -eq 1 ]; then
      echo -e "$(gum style --foreground "#00cc66" --bold "✓ 1 command deleted successfully")"
    else
      echo -e "$(gum style --foreground "#00cc66" --bold "✓ $selected_count commands deleted successfully")"
    fi
  else
    echo -e "$(gum style --foreground "#ffcc00" "Deletion cancelled")"
  fi
  
  read -n 1 -s -r -p "Press any key to continue..."
}
