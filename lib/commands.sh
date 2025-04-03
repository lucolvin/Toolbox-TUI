#!/bin/bash

# Function to add a new command
add_command() {
  name="$1"
  command_to_run="$2"
  description="$3"
  category="$4"
  
  # Debug output
  echo -e "${CYAN}Adding command with:${RESET}"
  echo -e "${CYAN}- Name: '$name'${RESET}"
  echo -e "${CYAN}- Command: '$command_to_run'${RESET}"
  echo -e "${CYAN}- Description: '$description'${RESET}"
  echo -e "${CYAN}- Category: '$category'${RESET}"
  
  # Ensure category is valid, default to "general" if empty
  if [ -z "$category" ]; then
    category="general"
    echo -e "${YELLOW}No category provided, using 'general'${RESET}"
  fi
  
  # Trim whitespace from category
  category=$(echo "$category" | xargs)
  
  # Check if command already exists
  if jq -e ".commands[\"$name\"]" "$DB_FILE" > /dev/null 2>&1; then
    echo -e "${YELLOW}Command '$name' already exists. Use modify to update it.${RESET}"
    return 1
  fi
  
  # Add the command to the database - with proper quoting of all arguments
  cat "$DB_FILE" | jq --arg name "$name" \
     --arg cmd "$command_to_run" \
     --arg desc "$description" \
     --arg cat "$category" \
     '.commands[$name] = {"command": $cmd, "description": $desc, "category": $cat}' \
     > "$DB_FILE.tmp" && mv "$DB_FILE.tmp" "$DB_FILE"
  
  echo -e "${GREEN}✓ Command '${BOLD}$name${RESET}${GREEN}' added successfully to category '${BOLD}$category${RESET}${GREEN}'.${RESET}"
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
  
  # Get list of categories with counts
  categories=$(jq -r '[.[].category] | unique | .[]' "$tmp_file" | sort)
  cat_count=$(echo "$categories" | wc -l | tr -d ' ')
  
  # Define box width for consistent borders
  box_width=50
  
  # Create horizontal line strings for reuse
  h_line=$(printf '%.0s─' $(seq 1 $box_width))
  
  # Display header with summary
  echo -e "\n${CYAN}${BOLD}╭${h_line}╮${RESET}"
  if [ -n "$category" ]; then
    # Calculate padding for centered text
    header_text=" Commands in category ${MAGENTA}${BOLD}$category${RESET}${CYAN}${BOLD} \($result_count found\) "
    # Strip color codes for length calculation using improved regex
    plain_text=$(echo -e "$header_text" | sed -r "s/\x1B\[([0-9]{1,3}(;[0-9]{1,3})*)?[mGK]//g")
    padding=$(( (box_width - ${#plain_text}) / 2 ))
    if [ $padding -lt 0 ]; then padding=0; fi
    left_pad=$(printf '%*s' $padding ' ')
    # Fix right padding calculation to ensure exact box width
    right_pad=$(printf '%*s' $((box_width - ${#plain_text} - padding)) ' ')
    echo -e "${CYAN}${BOLD}│${RESET}${left_pad}${header_text}${right_pad}${CYAN}${BOLD}│${RESET}"
  elif [ -n "$search_term" ]; then
    header_text=" Search results for ${YELLOW}${BOLD}\"$search_term\"${RESET}${CYAN}${BOLD} \($result_count found\) "
    # Strip color codes using improved regex
    plain_text=$(echo -e "$header_text" | sed -r "s/\x1B\[([0-9]{1,3}(;[0-9]{1,3})*)?[mGK]//g")
    padding=$(( (box_width - ${#plain_text}) / 2 ))
    if [ $padding -lt 0 ]; then padding=0; fi
    left_pad=$(printf '%*s' $padding ' ')
    right_pad=$(printf '%*s' $((box_width - ${#plain_text} - padding)) ' ')
    echo -e "${CYAN}${BOLD}│${RESET}${left_pad}${header_text}${right_pad}${CYAN}${BOLD}│${RESET}"
  else
    header_text=" All Commands ${CYAN}${BOLD}\($result_count in $cat_count categories\) "
    # Strip color codes using improved regex
    plain_text=$(echo -e "$header_text" | sed -r "s/\x1B\[([0-9]{1,3}(;[0-9]{1,3})*)?[mGK]//g")
    padding=$(( (box_width - ${#plain_text}) / 2 ))
    if [ $padding -lt 0 ]; then padding=0; fi
    left_pad=$(printf '%*s' $padding ' ')
    right_pad=$(printf '%*s' $((box_width - ${#plain_text} - padding)) ' ')
    echo -e "${CYAN}${BOLD}│${RESET}${left_pad}${header_text}${right_pad}${CYAN}${BOLD}│${RESET}"
  fi
  echo -e "${CYAN}${BOLD}╰${h_line}╯${RESET}\n"
  
  # Group and display by category
  for cat in $categories; do
    # Using tr for uppercase instead of ${var^^} for better compatibility
    cat_upper=$(echo "$cat" | tr '[:lower:]' '[:upper:]')
    
    # Box header for category
    echo -e "${MAGENTA}${BOLD}┌─ $cat_upper ${h_line:$((${#cat_upper} + 3))}┐${RESET}"
    
    # Get commands in this category
    jq -r --arg cat "$cat" 'to_entries | map(select(.value.category == $cat)) | sort_by(.key) | .[] | 
      "\(.key)\t\(.value.command)\t\(.value.description)"' "$tmp_file" | 
      while IFS=$'\t' read -r cmd_name cmd_command cmd_desc; do
        # Command name with icon - fill with spaces to right border
        cmd_display=" ${CYAN}${BOLD}▶ $cmd_name${RESET}"
        # Get actual width without color codes for padding calculation
        plain_cmd=$(echo -e "$cmd_display" | sed -r "s/\x1B\[([0-9]{1,3}(;[0-9]{1,3})*)?[mGK]//g")
        # Calculate padding precisely - adjusted to fix off-by-one error
        right_pad=$((box_width - ${#plain_cmd}))
        # Ensure we don't create negative padding
        if [ $right_pad -lt 0 ]; then right_pad=0; fi
        padding=$(printf '%*s' $right_pad ' ')
        echo -e "${MAGENTA}│${RESET}${cmd_display}${padding}${MAGENTA}│${RESET}"
        
        # Description (if available)
        if [ -n "$cmd_desc" ]; then
          # Truncate long descriptions to fit in the box
          desc_display="   ${YELLOW}$cmd_desc${RESET}"
          # Get actual width without color codes
          plain_desc=$(echo -e "$desc_display" | sed -r "s/\x1B\[([0-9]{1,3}(;[0-9]{1,3})*)?[mGK]//g")
          
          if [ ${#plain_desc} -gt $((box_width - 2)) ]; then
            # Calculate visible text length (without color codes)
            desc_text=${desc_display#*m}       # Remove first color code
            desc_text=${desc_text%${RESET}}    # Remove reset code
            visible_len=$((box_width - 6))
            
            # Truncate the visible text and add ellipsis
            truncated_desc="   ${YELLOW}${desc_text:0:$visible_len}...${RESET}"
            # Calculate padding based on visible length - adjusted
            right_pad=$((box_width - visible_len - 6))
            if [ $right_pad -lt 0 ]; then right_pad=0; fi
            padding=$(printf '%*s' $right_pad ' ')
            echo -e "${MAGENTA}│${RESET}${truncated_desc}${padding}${MAGENTA}│${RESET}"
          else
            # Normal padding for non-truncated descriptions - adjusted
            right_pad=$((box_width - ${#plain_desc}))
            if [ $right_pad -lt 0 ]; then right_pad=0; fi
            padding=$(printf '%*s' $right_pad ' ')
            echo -e "${MAGENTA}│${RESET}${desc_display}${padding}${MAGENTA}│${RESET}"
          fi
        fi
        
        # Command to run with subtle border (truncate if too long)
        cmd_display="   ${GREEN}$ $cmd_command${RESET}"
        # Get actual width without color codes
        plain_cmd_run=$(echo -e "$cmd_display" | sed -r "s/\x1B\[([0-9]{1,3}(;[0-9]{1,3})*)?[mGK]//g")
        
        if [ ${#plain_cmd_run} -gt $((box_width - 2)) ]; then
          # Calculate visible text length (without color codes)
          cmd_text=${cmd_display#*m}       # Remove first color code
          cmd_text=${cmd_text%${RESET}}    # Remove reset code
          visible_len=$((box_width - 6))
          
          # Truncate the visible text and add ellipsis
          truncated_cmd="   ${GREEN}${cmd_text:0:$visible_len}...${RESET}"
          # Calculate padding based on visible length - adjusted
          right_pad=$((box_width - visible_len - 6))
          if [ $right_pad -lt 0 ]; then right_pad=0; fi
          padding=$(printf '%*s' $right_pad ' ')
          echo -e "${MAGENTA}│${RESET}${truncated_cmd}${padding}${MAGENTA}│${RESET}"
        else
          # Normal padding for non-truncated commands - adjusted
          right_pad=$((box_width - ${#plain_cmd_run}))
          if [ $right_pad -lt 0 ]; then right_pad=0; fi
          padding=$(printf '%*s' $right_pad ' ')
          echo -e "${MAGENTA}│${RESET}${cmd_display}${padding}${MAGENTA}│${RESET}"
        fi
        
        # Add separator between commands in the same category - fixed padding calculation
        padding=$(printf '%*s' $((box_width)) ' ')
        echo -e "${MAGENTA}│${RESET}${padding}${MAGENTA}│${RESET}"
      done
    
    # Box footer
    echo -e "${MAGENTA}${BOLD}└${h_line}┘${RESET}\n"
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
