#!/bin/bash

# Extension Manager Script - Fetch VSCode Extension Info
# Compatible with the provided setup.sh structure

EXTENSIONS_FILE="$(pwd)/oss-extensions.txt"
OUTPUT_DIR="$(pwd)/extension_info"
DOWNLOAD_DIR="$(pwd)/downloads"

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
NC='\033[0m'

trap exit_trap SIGINT SIGTERM

exit_trap() {
    echo -e "\n\n${RED}[!]${NC} Operation interrupted. Cleaning up..."
    exit 1
}

log() {
    echo -e "\n${GREEN}[+]${NC} $1" >&2
}

error() {
    echo -e "${RED}[!]${NC} $1" >&2
}

info() {
    echo -e "${BLUE}[i]${NC} $1" >&2
}

warn() {
    echo -e "${YELLOW}[!]${NC} $1" >&2
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
    echo "Usage: $0 [-f | -d | -l | -c] [-h]"
    echo "  -f  Fetch extension information only"
    echo "  -d  Download VSIX files"
    echo "  -l  List extensions with versions"
    echo "  -c  Complete operation (fetch info + download + list)"
    echo "  -h  Display this help message"
}

check_dependencies() {
    local missing_deps=()
    
    if ! command -v curl &>/dev/null; then
        missing_deps+=("curl")
    fi
    
    if ! command -v jq &>/dev/null; then
        missing_deps+=("jq")
    fi
    
    if [ ${#missing_deps[@]} -gt 0 ]; then
        error "Missing dependencies: ${missing_deps[*]}"
        echo "Please install them:"
        echo "  - On Ubuntu/Debian: sudo apt install curl jq"
        echo "  - On Arch Linux: sudo pacman -S curl jq"
        echo "  - On RHEL/CentOS: sudo yum install curl jq"
        echo "  - On Void Linux: sudo xbps-install -S curl jq"
        exit 1
    fi
}

load_extensions() {
    local extensions=()
    
    if [ ! -f "$EXTENSIONS_FILE" ]; then
        error "Extensions file not found: $EXTENSIONS_FILE"
        exit 1
    fi
    
    while IFS= read -r line; do
        if [[ ! -z "$line" && ! "$line" =~ ^[[:space:]]*# ]]; then
            extensions+=("$line")
        fi
    done < "$EXTENSIONS_FILE"
    
    echo "${extensions[@]}"
}

fetch_extension_info() {
    local extension="$1"
    local namespace="${extension%.*}"
    local name="${extension#*.}"
    
    info "Fetching info for: $extension"
    
    local api_url="https://open-vsx.org/api/$namespace/$name"
    local response=$(curl -s -H "accept: application/json" "$api_url")
    
    if [ $? -ne 0 ] || [ -z "$response" ]; then
        error "Failed to fetch info for $extension"
        return 1
    fi
    
    if echo "$response" | jq -e '.error' >/dev/null 2>&1; then
        error "API error for $extension: $(echo "$response" | jq -r '.message // "Unknown error"')"
        return 1
    fi
    
    echo "$response"
}

save_extension_info() {
    log "Fetching extension information..."
    
    if ! ask_prompt "Do you want to fetch extension information from Open VSX?"; then
        warn "Operation cancelled..."
        return 0
    fi
    
    mkdir -p "$OUTPUT_DIR"
    
    local extensions=($(load_extensions))
    local total=${#extensions[@]}
    local count=0
    local failed=0
    
    echo "Processing $total extensions..."
    
    for extension in "${extensions[@]}"; do
        count=$((count + 1))
        echo "[$count/$total] Processing: $extension"
        
        local info=$(fetch_extension_info "$extension")
        if [ $? -eq 0 ]; then
            echo "$info" | jq > "$OUTPUT_DIR/${extension}.json"
            echo -e "${GREEN}✓${NC} Saved info for: $extension"
        else
            failed=$((failed + 1))
            echo -e "${RED}✗${NC} Failed to fetch: $extension"
        fi
    done
    
    log "Completed! Success: $((total - failed)), Failed: $failed"
}

download_extensions() {
    log "Downloading VSIX files..."
    
    if ! ask_prompt "Do you want to download VSIX files?"; then
        warn "Download cancelled..."
        return 0
    fi
    
    if [ ! -d "$OUTPUT_DIR" ]; then
        error "Extension info directory not found. Run with -f first."
        return 1
    fi
    
    mkdir -p "$DOWNLOAD_DIR"
    
    local count=0
    local failed=0
    
    for info_file in "$OUTPUT_DIR"/*.json; do
        if [ ! -f "$info_file" ]; then
            continue
        fi
        
        local extension=$(basename "$info_file" .json)
        local download_url=$(jq -r '.files.download // empty' "$info_file")
        local version=$(jq -r '.version // "unknown"' "$info_file")
        
        if [ -z "$download_url" ] || [ "$download_url" = "null" ]; then
            error "No download URL found for $extension"
            failed=$((failed + 1))
            continue
        fi
        
        count=$((count + 1))
        local filename="${extension}-${version}.vsix"
        
        info "Downloading: $filename"
        
        if curl -L -o "$DOWNLOAD_DIR/$filename" "$download_url" 2>/dev/null; then
            echo -e "${GREEN}✓${NC} Downloaded: $filename"
        else
            error "Failed to download: $filename"
            failed=$((failed + 1))
        fi
    done
    
    log "Download completed! Success: $((count - failed)), Failed: $failed"
}

list_extensions() {
    log "Listing extensions with versions..."
    
    if [ ! -d "$OUTPUT_DIR" ]; then
        error "Extension info directory not found. Run with -f first."
        return 1
    fi
    
    echo ""
    printf "%-40s %-15s %-50s\n" "Extension" "Version" "Display Name"
    printf "%-40s %-15s %-50s\n" "$(printf '%.0s-' {1..40})" "$(printf '%.0s-' {1..15})" "$(printf '%.0s-' {1..50})"
    
    for info_file in "$OUTPUT_DIR"/*.json; do
        if [ ! -f "$info_file" ]; then
            continue
        fi
        
        local extension=$(basename "$info_file" .json)
        local version=$(jq -r '.version // "N/A"' "$info_file")
        local display_name=$(jq -r '.displayName // .name // "N/A"' "$info_file")
        
        printf "%-40s %-15s %-50s\n" "$extension" "$version" "$display_name"
    done
    
    echo ""
    local total_extensions=$(find "$OUTPUT_DIR" -name "*.json" -type f | wc -l)
    log "Total extensions: $total_extensions"
}

generate_summary() {
    if [ ! -d "$OUTPUT_DIR" ]; then
        return
    fi
    
    local summary_file="$(pwd)/extension_summary.txt"
    
    {
        echo "VS Code Extensions Summary"
        echo "Generated: $(date)"
        echo "=========================="
        echo ""
        
        for info_file in "$OUTPUT_DIR"/*.json; do
            if [ ! -f "$info_file" ]; then
                continue
            fi
            
            local extension=$(basename "$info_file" .json)
            local version=$(jq -r '.version // "N/A"' "$info_file")
            local download_url=$(jq -r '.files.download // "N/A"' "$info_file")
            local description=$(jq -r '.description // "N/A"' "$info_file")
            
            echo "Extension: $extension"
            echo "Version: $version"
            echo "Download: $download_url"
            echo "Description: $description"
            echo "---"
        done
    } > "$summary_file"
    
    log "Summary saved to: $summary_file"
}

complete_operation() {
    log "Starting complete extension management..."
    
    if ! ask_prompt "Do you want to perform complete operation (fetch + download + list)?"; then
        warn "Complete operation cancelled..."
        return 0
    fi
    
    save_extension_info
    download_extensions
    list_extensions
    generate_summary
    
    log "Complete operation finished!"
}

# Main execution
check_dependencies

while getopts "fdlch" opt; do
    case $opt in
        f)
            clear
            save_extension_info
            ;;
        d)
            clear
            download_extensions
            ;;
        l)
            clear
            list_extensions
            ;;
        c)
            clear
            complete_operation
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
