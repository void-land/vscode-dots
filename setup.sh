#!/bin/bash

CORES=$(nproc)
VSCODE_DOTFILES_DIR="$(pwd)/configs"
VSCODE_EXTENSIONS_FILE="$(pwd)/extensions.txt"
VSCODE_TARGET_DIR="$HOME/.config/Code - OSS"

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

declare -a LOADED_EXTENSIONS=()
declare -a DEFAULT_EXTENSIONS=(
    "bradlc.vscode-tailwindcss"
)

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
    echo "Usage: $0 [-s | -u | -e | -c] [-h]"
    echo "  -s  Stow VS Code configuration files"
    echo "  -u  Unstow VS Code configuration files"
    echo "  -e  Install VS Code extensions"
    echo "  -c  Complete setup (stow configs + install extensions)"
    echo "  -h  Display this help message"
}

check_vscode_oss() {
    if ! command -v code-oss &> /dev/null; then
        error "VS Code OSS (code-oss) is not installed or not in PATH"
        echo "Please install VS Code OSS first:"
        echo "  - On Arch Linux: sudo pacman -S code"
        echo "  - On Void Linux: sudo xbps-install -S vscode"
        echo "  - On other systems: install code-oss package"
        exit 1
    fi
}

create_target_dirs() {
    log "Creating target directories..."
    mkdir -p "$VSCODE_TARGET_DIR"
    mkdir -p "$VSCODE_TARGET_DIR/User"
    echo "Created: $VSCODE_TARGET_DIR"
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

load_extensions() {
    LOADED_EXTENSIONS=()
    
    if [ -f "$VSCODE_EXTENSIONS_FILE" ]; then
        while IFS= read -r line; do
            if [[ ! -z "$line" && ! "$line" =~ ^[[:space:]]*# ]]; then
                LOADED_EXTENSIONS+=("$line")
            fi
        done < "$VSCODE_EXTENSIONS_FILE"
    else
        log "Extensions file not found, using default extensions"
        LOADED_EXTENSIONS=("${DEFAULT_EXTENSIONS[@]}")
    fi
}

install_extensions() {
    check_vscode_oss
    
    log "Installing VS Code extensions..."
    
    if ! ask_prompt "Do you want to install VS Code extensions?"; then
        error "Extension installation cancelled..."
        return 0
    fi
    
    load_extensions
    local extensions=("${LOADED_EXTENSIONS[@]}")

    if [ ${#extensions[@]} -eq 0 ]; then
        error "No extensions to install"
        return 0
    fi
    
    echo "Extensions to install:"
    for ext in "${extensions[@]}"; do
        echo "  - $ext"
    done
    
    if ! ask_prompt "Do you want to continue with installation?"; then
        error "Extension installation cancelled..."
        return 0
    fi
    
    for extension in "${extensions[@]}"; do
        echo "Installing: $extension"
        if code-oss --install-extension "$extension" --force; then
            echo -e "${GREEN}✓${NC} Successfully installed: $extension"
        else
            echo -e "${RED}✗${NC} Failed to install: $extension"
        fi
    done
    
    log "Extension installation completed"
}

install_extensions_concurrent() {
    check_vscode_oss
    
    log "Installing VS Code extensions..."
    
    if ! ask_prompt "Do you want to install VS Code extensions?"; then
        error "Extension installation cancelled..."
        return 0
    fi
    
    load_extensions
    local extensions=("${LOADED_EXTENSIONS[@]}")
    
    if [ ${#extensions[@]} -eq 0 ]; then
        error "No extensions to install"
        return 0
    fi
    
    echo "Extensions to install:"
    for ext in "${extensions[@]}"; do
        echo "  - $ext"
    done
    
    if ! ask_prompt "Do you want to continue with installation?"; then
        error "Extension installation cancelled..."
        return 0
    fi
    
    local max_concurrent="$CORES"
    local -a pids=()
    
    install_extension() {
        local extension="$1"
        echo "Installing: $extension"
        if code-oss --install-extension "$extension" --force; then
            echo -e "${GREEN}✓${NC} Successfully installed: $extension"
        else
            echo -e "${RED}✗${NC} Failed to install: $extension"
        fi
    }
    
    for extension in "${extensions[@]}"; do
        install_extension "$extension" &
        pids+=($!)
        
        # Wait if number of background jobs reaches max concurrent
        while [ ${#pids[@]} -ge $max_concurrent ]; do
            for i in "${!pids[@]}"; do
                if ! kill -0 "${pids[i]}" 2>/dev/null; then
                    unset 'pids[i]'
                fi
            done
            # Clean up array keys
            pids=(${pids[@]})
            sleep 0.1
        done
    done
    
    # Wait for all background jobs to finish
    for pid in "${pids[@]}"; do
        wait $pid
    done
    
    log "Extension installation completed"
}

install_extensions_parallel() {
    check_vscode_oss
    
    log "Installing VS Code extensions..."
    
    if ! ask_prompt "Do you want to install VS Code extensions?"; then
        error "Extension installation cancelled..."
        return 0
    fi
    
    load_extensions
    local extensions=("${LOADED_EXTENSIONS[@]}")
    
    if [ ${#extensions[@]} -eq 0 ]; then
        error "No extensions to install"
        return 0
    fi
    
    echo "Extensions to install:"
    for ext in "${extensions[@]}"; do
        echo "  - $ext"
    done
    
    if ! ask_prompt "Do you want to continue with installation?"; then
        error "Extension installation cancelled..."
        return 0
    fi
    
    if ! command -v parallel &> /dev/null; then
        error "GNU parallel is not installed. Please install it first:"
        echo "  - On Ubuntu/Debian: sudo apt install parallel"
        echo "  - On RHEL/CentOS: sudo yum install parallel"
        echo "  - On Arch: sudo pacman -S parallel"
        echo "  - On Void: sudo xbps-install -S parallel"
        return 1
    fi
    
    install_single_extension() {
        local extension="$1"
        local start_time=$(date +%s)
        local temp_file=$(mktemp)
        
        echo "🔄 Starting installation: $extension"
        
        if code-oss --install-extension "$extension" --force &> "$temp_file"; then
            local end_time=$(date +%s)
            local duration=$((end_time - start_time))
            echo -e "${GREEN}✓${NC} Successfully installed: $extension (${duration}s)"
        else
            echo -e "${RED}✗${NC} Failed to install: $extension"
            echo "Error details:"
            cat "$temp_file" | head -5
        fi
        
        rm -f "$temp_file"
    }
    
    export -f install_single_extension
    export GREEN RED NC
    
    echo "Starting parallel installation of ${#extensions[@]} extensions..."
    
    printf '%s\n' "${extensions[@]}" | \
        parallel \
        --jobs $CORES \
        --progress \
        --bar \
        --eta \
        --joblog /tmp/vscode_extensions.log \
        install_single_extension
    
    # Show summary
    echo ""
    echo "Installation Summary:"
    echo "====================="
    if [ -f /tmp/vscode_extensions.log ]; then
        local total=$(wc -l < /tmp/vscode_extensions.log)
        local succeeded=$(grep -c "^[^#].*\s0\s" /tmp/vscode_extensions.log || echo "0")
        local failed=$((total - succeeded))
        
        echo "Total extensions: $total"
        echo "Succeeded: $succeeded"
        echo "Failed: $failed"
        
        if [ $failed -gt 0 ]; then
            echo ""
            echo "Failed extensions:"
            grep "^[^#].*\s[^0]\s" /tmp/vscode_extensions.log | awk '{print "  - " $NF}'
        fi
    fi
    
    log "Extension installation completed"
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
        log "VS Code dotfiles unstowed successfully!"
    else
        error "VS Code dotfiles directory not found: $VSCODE_DOTFILES_DIR"
        return 1
    fi
}

complete_setup() {
    log "Starting complete VS Code setup..."
    
    if ! ask_prompt "Do you want to perform complete VS Code setup (stow configs + install extensions)?"; then
        error "Complete setup cancelled..."
        return 0
    fi
    
    stow_config
    install_extensions
    
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
        e)
            clear
            install_extensions_concurrent
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
