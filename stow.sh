#!/bin/bash

CORES=$(nproc)
VSCODE_DOTFILES_DIR="$(pwd)/configs"
VSCODE_EXTENSIONS_FILE="$(pwd)/oss-extensions.txt"
VSCODE_TARGET_DIR="$HOME/.config/Code - OSS"
VSCODIUM_TARGET_DIR="$HOME/.config/VSCodium"

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

# Trap for clean exit
trap exit_trap SIGINT SIGTERM

exit_trap() {
    echo -e "\n\n${RED}[!]${NC} Installation interrupted. Cleaning up..."
    # pkill -P $$ 2>/dev/null
    exit 1
}

try() {
    local log_file=$(mktemp)
    if ! eval "$@" &>"$log_file"; then
        echo -e "${RED}[!]${NC} Failed: $*"
        cat "$log_file"
        rm -f "$log_file"
        exit 1
    fi
    rm -f "$log_file"
}

log() {
    echo -e "\n${GREEN}[+]${NC} $1" >&2
}

error() {
    echo -e "${RED}[!]${NC} $1" >&2
}

ask_prompt() {
    local question="$1"
    while true; do
        read -p "$question (Y/N): " choice
        case "$choice" in
            [Yy]) return 0 ;;
            [Nn]) return 1 ;;
            *) echo "Please enter Y or N." ;;
        esac
    done
}

display_help() {
    echo "Usage: $0 [-s | -u | -c] [-h]"
    echo "  -s  Stow VS Code configuration files"
    echo "  -u  Unstow VS Code configuration files"
    echo "  -c  Complete setup (stow configs)"
    echo "  -h  Display this help message"
}

check_vscode_oss() {
    if ! command -v code-oss &> /dev/null; then
        error "VS Code OSS (code-oss) is not installed or not in PATH"
        echo "Please install VS Code OSS first:"
        echo "  - On Arch Linux: sudo pacman -S code | yay -S vscodium"
        echo "  - On Void Linux: sudo xbps-install -S vscode"
        echo "  - On other systems: install code-oss | vscodium package"
        exit 1
    fi
}

create_target_dirs() {
    log "Creating target directories..."
    mkdir -p "$VSCODE_TARGET_DIR"
    mkdir -p "$VSCODE_TARGET_DIR/User"
    
    mkdir -p "$VSCODIUM_TARGET_DIR"
    mkdir -p "$VSCODIUM_TARGET_DIR/User"

    echo "Created: $VSCODE_TARGET_DIR"
    echo "Created: $VSCODIUM_TARGET_DIR"
}

create_link() {
    local source=$1
    local target=$2
    
    if [ ! -e "$source" ]; then
        echo "Source does not exist: $source"
        return 1
    fi
    
    if [ ! -d "$(dirname "$target")" ]; then
        mkdir -p "$(dirname "$target")"
    fi
    
    if [ -e "$target" ]; then
        rm -rf "$target"
    fi
    
    ln -sfn "$source" "$target"
    echo "$source ===> $target"
}

create_links() {
    local source_dir=$1
    local target_dir=$2
    
    if [ ! -d "$source_dir" ]; then
        echo "Source directory does not exist: $source_dir"
        return 1
    fi
    
    if [ ! -d "$target_dir" ]; then
        mkdir -p "$target_dir"
    fi
    
    for item in "$source_dir"/* "$source_dir"/.*; do
        if [ -e "$item" ] && [ "$item" != "$source_dir/." ] && [ "$item" != "$source_dir/.." ]; then
            local item_name=$(basename "$item")
            local target_path="$target_dir/$item_name"
            
            # Remove existing directory if it exists
            if [ -d "$target_path" ]; then
                rm -rf "$target_path"
                echo "Removed existing directory: $target_path"
            fi
            
            echo "$item ===> $target_dir"
            ln -sfn "$item" "$target_dir/"
        fi
    done
}


delete_links() {
    local source_dir=$1
    local target_dir=$2
    
    if [ ! -d "$source_dir" ] || [ ! -d "$target_dir" ]; then
        echo "Source or target directory does not exist."
        return 1
    fi
    
    for config in "$source_dir"/* "$source_dir"/.*; do
        config_name=$(basename "$config")
        target_config="$target_dir/$config_name"
        
        if [ -e "$target_config" ]; then
            rm -rf "$target_config"
            echo "Removed: $target_config"
        else
            echo "Not found: $target_config"
        fi
    done
}

stow_config() {
    log "Stowing VS Code configuration..."
    
    if ! ask_prompt "Do you want to stow VS Code configuration files?"; then
        error "Stowing cancelled..."
        return 0
    fi
    
    create_target_dirs
    
    if [ -d "$VSCODE_DOTFILES_DIR" ]; then
        create_links "$VSCODE_DOTFILES_DIR" "$VSCODE_TARGET_DIR/User"
        create_links "$VSCODE_DOTFILES_DIR" "$VSCODIUM_TARGET_DIR/User"

        log "VS Code dotfiles stowed successfully!"
    else
        error "VS Code dotfiles directory not found: $VSCODE_DOTFILES_DIR"
        return 1
    fi
}

unstow_config() {
    log "Unstowing VS Code configuration..."
    
    if ! ask_prompt "Do you want to unstow VS Code configuration files?"; then
        error "Unstowing cancelled..."
        return 0
    fi
    
    if [ -d "$VSCODE_DOTFILES_DIR" ]; then
        delete_links "$VSCODE_DOTFILES_DIR" "$VSCODE_TARGET_DIR/User"
        delete_links "$VSCODE_DOTFILES_DIR" "$VSCODIUM_TARGET_DIR/User"

        log "VS Code dotfiles unstowed successfully!"
    else
        error "VS Code dotfiles directory not found: $VSCODE_DOTFILES_DIR"
        return 1
    fi
}

complete_setup() {
    log "Starting complete VS Code setup..."
    
    if ! ask_prompt "Do you want to perform complete VS Code setup (stow configs)?"; then
        error "Complete setup cancelled..."
        return 0
    fi
    
    stow_config
    
    log "Complete VS Code setup finished!"
}

while getopts "suech" opt; do
    case $opt in
        s)
            clear
            stow_config
            ;;
        u)
            clear
            unstow_config
            ;;
        c)
            clear
            complete_setup
            ;;
        h)
            display_help
            exit 0
            ;;
        *)
            display_help
            exit 1
            ;;
    esac
done

if [[ $# -eq 0 ]]; then
    display_help
fi
