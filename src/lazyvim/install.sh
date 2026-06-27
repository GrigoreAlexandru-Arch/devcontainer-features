#!/usr/bin/env bash
set -e

# Fetch options from devcontainer-feature.json
NVIM_VERSION=${VERSION:-"stable"}
CONFIG_REPO=${CONFIGREPO:-"https://github.com/LazyVim/starter"}
EXTRAS=${EXTRAS:-""}

echo "Activating feature 'LazyVim'"

# 1. Install System Dependencies
echo "Installing system dependencies..."
apt-get update
apt-get install -y --no-install-recommends \
    git \
    curl \
    ca-certificates \
    build-essential \
    ripgrep \
    fd-find \
    xclip \
    jq \
    unzip \
    gzip \
    python3 \
    python3-pip \
    python3-venv \
    python3-pynvim \
    luarocks \
    sqlite3 \
    libsqlite3-dev

# 2. Helper function to fetch GitHub assets safely and avoid rate limits
fetch_github_asset() {
    local api_url=$1
    local pattern=$2

    local CURL_OPTS=("-s")
    if [ -n "${GITHUB_TOKEN}" ]; then
        CURL_OPTS+=("-H" "Authorization: Bearer ${GITHUB_TOKEN}")
    fi

    local response
    response=$(curl "${CURL_OPTS[@]}" "$api_url")

    # If the response contains a "message" field, it's likely an API error (e.g., rate limiting)
    local error_msg
    error_msg=$(echo "$response" | jq -r '.message // empty')

    if [ -n "$error_msg" ]; then
        echo "Error: GitHub API request failed." >&2
        echo "API Response: $error_msg" >&2
        echo "Target URL: $api_url" >&2
        exit 1
    fi

    # Safely parse the assets array
    echo "$response" | jq -r '.assets[].browser_download_url // empty' | grep -E "$pattern" | head -n 1
}

# 3. Determine Architecture
ARCH=$(uname -m)
echo "Detected architecture: $ARCH"

if [ "$ARCH" = "x86_64" ]; then
    ASSET_PATTERN="nvim-linux-x86_64\.tar\.gz|nvim-linux64\.tar\.gz"
    FZF_ARCH="amd64"
    TS_ARCH="x64"
    WIN32YANK_ARCH="x64"
elif [ "$ARCH" = "aarch64" ]; then
    ASSET_PATTERN="nvim-linux-arm64\.tar\.gz"
    FZF_ARCH="arm64"
    TS_ARCH="arm64"
else
    echo "Unsupported architecture: $ARCH"
    exit 1
fi

# 4. Determine the GitHub API Endpoint for Neovim
if [ "${NVIM_VERSION}" = "stable" ]; then
    API_URL="https://api.github.com/repos/neovim/neovim/releases/latest"
elif [ "${NVIM_VERSION}" = "nightly" ]; then
    API_URL="https://api.github.com/repos/neovim/neovim/releases/tags/nightly"
else
    API_URL="https://api.github.com/repos/neovim/neovim/releases/tags/${NVIM_VERSION}"
fi

# 5. Fetch and install Neovim
echo "Querying GitHub API for Neovim release: ${NVIM_VERSION}..."
DOWNLOAD_URL=$(fetch_github_asset "$API_URL" "$ASSET_PATTERN")

if [ -z "$DOWNLOAD_URL" ]; then
    echo "Error: Could not find a valid Neovim asset for architecture $ARCH in release ${NVIM_VERSION}."
    exit 1
fi

echo "Downloading Neovim from: $DOWNLOAD_URL"
curl -LO -f "$DOWNLOAD_URL"
FILENAME=$(basename "$DOWNLOAD_URL")

tar -C /opt -xzf "$FILENAME"
rm "$FILENAME"

EXTRACTED_DIR=$(find /opt -maxdepth 1 -name "nvim-linux*" -type d | head -n 1)

if [ -z "$EXTRACTED_DIR" ]; then
    echo "Error: Failed to find extracted Neovim directory in /opt."
    exit 1
fi

ln -s "${EXTRACTED_DIR}/bin/nvim" /usr/local/bin/nvim

# 6. Install External Binaries (FZF, Tree-Sitter)
echo "Installing external binaries..."

# Download and setup fzf
echo "Fetching latest fzf release..."
FZF_LATEST_URL=$(fetch_github_asset "https://api.github.com/repos/junegunn/fzf/releases/latest" "linux_${FZF_ARCH}\.tar\.gz")
curl -LO -f "$FZF_LATEST_URL"
tar -xzf $(basename "$FZF_LATEST_URL")
mv fzf /usr/local/bin/
rm $(basename "$FZF_LATEST_URL")

# Download and setup tree-sitter-cli
echo "Fetching latest tree-sitter release..."
TS_LATEST_URL=$(fetch_github_asset "https://api.github.com/repos/tree-sitter/tree-sitter/releases/latest" "tree-sitter-linux-${TS_ARCH}\.gz")
curl -LO -f "$TS_LATEST_URL"
gzip -d $(basename "$TS_LATEST_URL")
chmod +x "tree-sitter-linux-${TS_ARCH}"
mv "tree-sitter-linux-${TS_ARCH}" /usr/local/bin/tree-sitter

# 7. Determine Target User and Home Directory for Build Time
TARGET_USER=${_REMOTE_USER:-"root"}
TARGET_HOME=${_REMOTE_USER_HOME:-$HOME}
CONFIG_DIR="${TARGET_HOME}/.config/nvim"

echo "Targeting user: ${TARGET_USER} with home: ${TARGET_HOME}"

if [ -d "$CONFIG_DIR" ]; then
    echo "Neovim configuration already exists at $CONFIG_DIR. Skipping setup."
    exit 0
fi

# 8. Setup Configuration and Install Plugins
echo "Cloning LazyVim configuration..."
mkdir -p "${TARGET_HOME}/.config"

# Ensure GitHub is in known_hosts to prevent interactive prompts
mkdir -p "${TARGET_HOME}/.ssh"
chmod 700 "${TARGET_HOME}/.ssh"
ssh-keyscan github.com >>"${TARGET_HOME}/.ssh/known_hosts" 2>/dev/null

# Set correct ownership BEFORE cloning so the target user can write to these directories
chown -R "${TARGET_USER}:${TARGET_USER}" "${TARGET_HOME}/.config" "${TARGET_HOME}/.ssh"

# Clone the repository as the target user
echo "Cloning repository as ${TARGET_USER}..."
if [ "${TARGET_USER}" != "root" ]; then
    su - "${TARGET_USER}" -c "git clone ${CONFIG_REPO} ${CONFIG_DIR}"
else
    git clone "${CONFIG_REPO}" "$CONFIG_DIR"
fi

# 9. Handle LazyVim Extras
if [ -n "$EXTRAS" ]; then
    echo "Configuring LazyVim extras: $EXTRAS"
    LAZYVIM_JSON="${CONFIG_DIR}/lazyvim.json"

    # Convert comma-separated string to JSON array (stripping spaces) and map to { "extras": [...] }
    if [ ! -f "$LAZYVIM_JSON" ]; then
        echo "$EXTRAS" | jq -R -c 'split(",") | map(select(length > 0) | sub("^\\s+";"") | sub("\\s+$";"")) | {extras: .}' >"$LAZYVIM_JSON"
    else
        # If lazyvim.json already exists in the cloned repo, append and keep unique items
        EXTRAS_ARRAY=$(echo "$EXTRAS" | jq -R -c 'split(",") | map(select(length > 0) | sub("^\\s+";"") | sub("\\s+$";""))')
        jq --argjson new "$EXTRAS_ARRAY" '.extras = ((.extras // []) + $new | unique)' "$LAZYVIM_JSON" >"${LAZYVIM_JSON}.tmp" && mv "${LAZYVIM_JSON}.tmp" "$LAZYVIM_JSON"
    fi

    # Fix ownership of lazyvim.json
    chown "${TARGET_USER}:${TARGET_USER}" "$LAZYVIM_JSON"
fi

echo "Bootstrapping LazyVim plugins headlessly..."
# Run the plugin sync as the target user to ensure paths (~/.local/share/nvim)
# and permissions are set properly for development.
if [ "${TARGET_USER}" != "root" ]; then
    su - "${TARGET_USER}" -c "nvim --headless '+Lazy! sync' +qa"
else
    nvim --headless '+Lazy! sync' +qa
fi

echo "LazyVim installation and build-time feature setup complete!"
