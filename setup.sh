#!/usr/bin/env sh
set -eu

arch="$(uname -m)"
platform="$(uname -s)"

NAME="code"
CHANNEL="${VSCODE_BUILD:-code-oss}"

local_bin_path="$HOME/.local/bin"
local_application_path="$HOME/.local/share/applications"
app_installation_path="$HOME/.local/vscode-stable"

main() {

}