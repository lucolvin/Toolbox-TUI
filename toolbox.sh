#!/bin/bash

# Toolbox - A terminal tool for managing command shortcuts
# Usage: toolbox command [arguments]

# Get the directory where the script is located, resolving symlinks
if command -v readlink >/dev/null 2>&1 && [[ -L "$0" ]]; then
  # For systems with readlink, resolve symlinks
  SCRIPT_PATH=$(readlink -f "$0" 2>/dev/null || readlink "$0" 2>/dev/null || echo "$0")
  SCRIPT_DIR=$(dirname "$SCRIPT_PATH")
else
  # Fallback method if readlink is not available
  SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
fi

# Look for lib directory in different possible locations
LIB_DIR="$SCRIPT_DIR/lib"
if [ ! -d "$LIB_DIR" ]; then
  # Try common installation paths
  for dir in "/usr/local/share/toolbox/lib" "$HOME/.toolbox/lib" "/opt/toolbox/lib" "$HOME/.local/share/toolbox/lib"; do
    if [ -d "$dir" ]; then
      LIB_DIR="$dir"
      break
    fi
  done
fi

# Create a shell script to install the libraries if they don't exist
if [ ! -d "$LIB_DIR" ]; then
  echo "Library directory not found. Installing..."
  
  # Determine install location
  INSTALL_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/toolbox"
  mkdir -p "$INSTALL_DIR/lib"
  LIB_DIR="$INSTALL_DIR/lib"
  
  # Copy module files if this script is the original (not a symlink)
  if [ -f "$SCRIPT_DIR/lib/config.sh" ]; then
    cp -r "$SCRIPT_DIR/lib" "$INSTALL_DIR/"
    echo "Libraries installed to $INSTALL_DIR/lib"
  else
    echo "ERROR: Cannot find library files to install."
    echo "Please run the original script from its source directory first,"
    echo "or manually set up the lib directory at $LIB_DIR"
    exit 1
  fi
fi

# Source the module files
source "$LIB_DIR/config.sh"
source "$LIB_DIR/utils.sh"
source "$LIB_DIR/commands.sh"
source "$LIB_DIR/tui.sh"
source "$LIB_DIR/import_export.sh"
source "$LIB_DIR/search.sh"

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
      
      # If no additional arguments, go to TUI mode
      if [ $# -eq 0 ]; then
        echo -e "${YELLOW}For interactive modification, please use 'toolbox' and select 'Modify Command'.${RESET}"
        exit 0
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
        run_tui_mode
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