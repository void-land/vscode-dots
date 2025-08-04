#!/bin/bash

# Extension Manager Script - Fetch VSCode Extension Info
# Compatible with the provided setup.sh structure

EXTENSIONS_FILE="$(pwd)/oss-extensions.txt"
DOWNLOAD_DIR="$(pwd)/downloads"
OUTPUT_DIR="$(pwd)/extension_info"
INSTALL_LOG="$(pwd)/install.log"

# Color codes (matching your setup.sh style)
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
NC='\033[0m'

# Trap for clean exit
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
    echo "Usage: $0 [-f | -d | -v | -p | -l | -c] [-h]"
    echo "  -f  Fetch extension information only"
    echo "  -d  Download VSIX files (sequential)"
    echo "  -v  Install from VSIX files (downloaded files)"
    echo "  -p  Download VSIX files (concurrent - 6 parallel downloads)"
    echo "  -l  List extensions with versions"
    echo "  -c  Complete operation (fetch info + parallel download + list)"
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

check_curl_parallel_support() {
    local curl_version=$(curl --version | head -n1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n1)
    local required_version="7.66.0"
    
    if ! printf '%s\n%s\n' "$required_version" "$curl_version" | sort -V | head -n1 | grep -q "^$required_version$"; then
        warn "curl version $curl_version detected. Native parallel download requires curl 7.66.0 or newer."
        warn "Falling back to background processes method..."
        return 1
    fi
    
    log "curl version $curl_version supports native parallel downloads (-Z flag)"
    return 0
}

check_parallel_dependency() {
    if ! command -v parallel &>/dev/null; then
        error "GNU parallel is not installed. Please install it first:"
        echo "  - On Ubuntu/Debian: sudo apt install parallel"
        echo "  - On Arch Linux: sudo pacman -S parallel"
        echo "  - On RHEL/CentOS: sudo yum install parallel"
        echo "  - On Void Linux: sudo xbps-install -S parallel"
        echo ""
        warn "Falling back to sequential download..."
        return 1
    fi
    return 0
}

detect_vscode() {
    local vscode_commands=("code" "code-insiders" "codium")
    local found_command=""
    
    for cmd in "${vscode_commands[@]}"; do
        if command -v "$cmd" &>/dev/null; then
            found_command="$cmd"
            break
        fi
    done
    
    if [ -z "$found_command" ]; then
        error "VS Code not found. Please install one of: code, code-insiders, codium"
        echo "Installation instructions:"
        echo "  - Official VS Code: https://code.visualstudio.com/"
        echo "  - VS Code Insiders: https://code.visualstudio.com/insiders/"
        echo "  - VSCodium: https://vscodium.com/"
        exit 1
    fi
    
    log "Found VS Code command: $found_command"
    echo "$found_command"
}

load_extensions() {
    local extensions=()
    
    if [ ! -f "$EXTENSIONS_FILE" ]; then
        error "Extensions file not found: $EXTENSIONS_FILE"
        exit 1
    fi
    
    while IFS= read -r line; do
        # Skip empty lines and comments
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
    
    # Check if response contains error
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
            echo "$info" > "$OUTPUT_DIR/${extension}.json"
            echo -e "${GREEN}✓${NC} Saved info for: $extension"
        else
            failed=$((failed + 1))
            echo -e "${RED}✗${NC} Failed to fetch: $extension"
        fi
    done
    
    log "Completed! Success: $((total - failed)), Failed: $failed"
}

# Sequential download function (original)
download_extensions() {
    log "Downloading VSIX files (sequential)..."
    
    if ! ask_prompt "Do you want to download VSIX files sequentially?"; then
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

# Concurrent download function (new)
download_extensions_parallel() {
    log "Downloading VSIX files concurrently (6 parallel downloads)..."
    
    if ! ask_prompt "Do you want to download VSIX files concurrently?"; then
        warn "Concurrent download cancelled..."
        return 0
    fi

    if [ ! -d "$OUTPUT_DIR" ]; then
        error "Extension info directory not found. Run with -f first."
        return 1
    fi

    if ! check_parallel_dependency; then
        download_extensions_concurrent
        return
    fi

    mkdir -p "$DOWNLOAD_DIR"

    # Function to download a single extension
    download_single() {
        local info_file="$1"
        local extension=$(basename "$info_file" .json)
        local download_url=$(jq -r '.files.download // empty' "$info_file")
        local version=$(jq -r '.version // "unknown"' "$info_file")

        if [ -z "$download_url" ] || [ "$download_url" = "null" ]; then
            echo -e "${RED}[!]${NC} No download URL found for $extension" >&2
            return 1
        fi

        local filename="${extension}-${version}.vsix"
        local temp_file=$(mktemp)
        
        echo -e "${BLUE}[i]${NC} Starting download: $filename" >&2

        if curl -L -o "$DOWNLOAD_DIR/$filename" "$download_url" &>"$temp_file"; then
            echo -e "${GREEN}✓${NC} Downloaded: $filename" >&2
        else
            echo -e "${RED}✗${NC} Failed to download: $filename" >&2
            cat "$temp_file" | head -3 >&2
            rm -f "$temp_file"
            return 1
        fi
        
        rm -f "$temp_file"
        return 0
    }

    export -f download_single
    export GREEN RED BLUE NC
    export OUTPUT_DIR DOWNLOAD_DIR

    local total_files=$(find "$OUTPUT_DIR" -name '*.json' -type f | wc -l)
    echo "Starting parallel download of $total_files extensions with 6 concurrent downloads..."

    # Use GNU parallel to download with max concurrency 6
    if find "$OUTPUT_DIR" -name '*.json' -type f | \
       parallel --jobs 6 --progress --bar --eta download_single {}; then
        
        # Count successful downloads
        local downloaded=$(find "$DOWNLOAD_DIR" -name '*.vsix' -type f | wc -l)
        local failed=$((total_files - downloaded))
        
        echo ""
        log "Concurrent downloads completed!"
        echo "Total extensions: $total_files"
        echo "Successfully downloaded: $downloaded"
        echo "Failed: $failed"
        
        if [ $failed -gt 0 ]; then
            warn "Some downloads failed. Check the output above for details."
        fi
    else
        error "Parallel download failed. Some extensions may not have been downloaded."
    fi
}

# Concurrent download curl (new)
download_extensions_curl_parallel() {
    log "Downloading VSIX files using curl native parallel download..."
    
    if ! ask_prompt "Do you want to download VSIX files using curl parallel download?"; then
        warn "Parallel download cancelled..."
        return 0
    fi

    if [ ! -d "$OUTPUT_DIR" ]; then
        error "Extension info directory not found. Run with -f first."
        return 1
    fi

    mkdir -p "$DOWNLOAD_DIR"

    if ! check_curl_parallel_support; then
        download_extensions
        return
    fi

    local config_file="$(pwd)/downloads/links.txt"
    local total_files=0
    local valid_files=0

    info "Preparing download configuration..."

    for info_file in "$OUTPUT_DIR"/*.json; do
        if [ ! -f "$info_file" ]; then
            continue
        fi
        
        total_files=$((total_files + 1))
        local extension=$(basename "$info_file" .json)
        local download_url=$(jq -r '.files.download // empty' "$info_file")
        local version=$(jq -r '.version // "unknown"' "$info_file")
        
        if [ -z "$download_url" ] || [ "$download_url" = "null" ]; then
            warn "No download URL found for $extension"
            continue
        fi
        
        local filename="${extension}-${version}.vsix"
        
        # Add to curl config file
        echo "url = \"$download_url\"" >> "$config_file"
        echo "output = \"$DOWNLOAD_DIR/$filename\"" >> "$config_file"
        echo "" >> "$config_file"
        
        valid_files=$((valid_files + 1))
    done

    if [ $valid_files -eq 0 ]; then
        error "No valid download URLs found"
        rm -f "$config_file"

        return 1
    fi

    echo "Starting parallel download of $valid_files extensions..."
    echo "Configuration prepared for curl parallel download"

    # Use curl with parallel flag and config file
    if curl -O -L --parallel --parallel-max 20 --config "$config_file" --show-error; then
        log "Parallel downloads completed successfully!"
        
        # Count successful downloads
        local downloaded=$(find "$DOWNLOAD_DIR" -name '*.vsix' -type f | wc -l)
        local failed=$((valid_files - downloaded))
        
        echo "Total extensions: $total_files"
        echo "Valid URLs: $valid_files"
        echo "Successfully downloaded: $downloaded"
        echo "Failed: $failed"
        
        if [ $failed -gt 0 ]; then
            warn "Some downloads failed. Files may be corrupted or URLs may be invalid."
        fi
    else
        error "Curl parallel download failed..."

        return
    fi

    rm -f "$config_file"
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


install_from_vsix() {
    log "Installing extensions from VSIX files..."
    
    if ! ask_prompt "Do you want to install extensions from downloaded VSIX files?"; then
        warn "Installation cancelled..."
        return 0
    fi
    
    if [ ! -d "$DOWNLOAD_DIR" ]; then
        error "Download directory not found: $DOWNLOAD_DIR"
        error "Please run the extension manager with -d or -p to download VSIX files first."
        return 1
    fi
    
    local vscode_cmd=$(detect_vscode)
    local vsix_files=($(find "$DOWNLOAD_DIR" -name "*.vsix" -type f))
    
    if [ ${#vsix_files[@]} -eq 0 ]; then
        error "No VSIX files found in $DOWNLOAD_DIR"
        error "Please download extensions first using the extension manager."
        return 1
    fi
    
    local total=${#vsix_files[@]}
    local count=0
    local success=0
    local failed=0
    
    # Initialize log file
    echo "Extension Installation Log - $(date)" > "$INSTALL_LOG"
    echo "========================================" >> "$INSTALL_LOG"
    echo "" >> "$INSTALL_LOG"
    
    echo "Found $total VSIX files to install..."
    
    for vsix_file in "${vsix_files[@]}"; do
        count=$((count + 1))
        local filename=$(basename "$vsix_file")
        
        echo "[$count/$total] Installing: $filename"
        
        if $vscode_cmd --install-extension "$vsix_file" --force &>/dev/null; then
            success=$((success + 1))
            echo -e "${GREEN}✓${NC} Installed: $filename"
            echo "[SUCCESS] $filename" >> "$INSTALL_LOG"
        else
            failed=$((failed + 1))
            echo -e "${RED}✗${NC} Failed: $filename"
            echo "[FAILED] $filename" >> "$INSTALL_LOG"
        fi
    done
    
    echo "" >> "$INSTALL_LOG"
    echo "Summary: $success successful, $failed failed" >> "$INSTALL_LOG"
    
    log "Installation completed!"
    echo "Total: $total, Success: $success, Failed: $failed"
    echo "Log saved to: $INSTALL_LOG"
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
    
    if ! ask_prompt "Do you want to perform complete operation (fetch + parallel download + local install + list)?"; then
        warn "Complete operation cancelled..."
        return 0
    fi
    
    save_extension_info
    download_extensions_curl_parallel
    install_from_vsix
    list_extensions
    generate_summary
    
    log "Complete operation finished!"
}



# Main execution
check_dependencies

while getopts "fdplchv" opt; do
    case $opt in
        v)
            clear 
            install_from_vsix
            ;;
        f)
            clear
            save_extension_info
            ;;
        d)
            clear
            download_extensions
            ;;
        p)
            clear
            download_extensions_curl_parallel
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
