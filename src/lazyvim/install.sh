#!/usr/bin/env bash
set -e

# Fetch options from devcontainer-feature.json
NVIM_VERSION=${VERSION:-"stable"}
CONFIG_REPO=${CONFIGREPO:-"https://github.com/LazyVim/starter"}

echo "Activating feature 'LazyVim'"

# 1. Install System Dependencies
apt-get update
apt-get install -y --no-install-recommends \
    git \
    curl \
    ca-certificates \
    build-essential \
    ripgrep \
    fd-find \
    xclip \
    jq

# 2. Determine Architecture
ARCH=$(uname -m)
echo "Detected architecture: $ARCH"

if [ "$ARCH" = "x86_64" ]; then
    ASSET_PATTERN="nvim-linux-x86_64\.tar\.gz|nvim-linux64\.tar\.gz"
elif [ "$ARCH" = "aarch64" ]; then
    ASSET_PATTERN="nvim-linux-arm64\.tar\.gz"
else
    echo "Unsupported architecture: $ARCH"
    exit 1
fi

# 3. Determine the GitHub API Endpoint
if [ "${NVIM_VERSION}" = "stable" ]; then
    API_URL="https://api.github.com/repos/neovim/neovim/releases/latest"
elif [ "${NVIM_VERSION}" = "nightly" ]; then
    API_URL="https://api.github.com/repos/neovim/neovim/releases/tags/nightly"
else
    API_URL="https://api.github.com/repos/neovim/neovim/releases/tags/${NVIM_VERSION}"
fi

# 4. Fetch and install Neovim
echo "Querying GitHub API for Neovim release: ${NVIM_VERSION}..."
DOWNLOAD_URL=$(curl -s "$API_URL" | jq -r '.assets[].browser_download_url' | grep -E "$ASSET_PATTERN" | head -n 1)

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

# 5. Determine Target User and Home Directory for Build Time
# Devcontainers provide $_REMOTE_USER and $_REMOTE_USER_HOME during features execution
TARGET_USER=${_REMOTE_USER:-"root"}
TARGET_HOME=${_REMOTE_USER_HOME:-$HOME}
CONFIG_DIR="${TARGET_HOME}/.config/nvim"

echo "Targeting user: ${TARGET_USER} with home: ${TARGET_HOME}"

if [ -d "$CONFIG_DIR" ]; then
    echo "Neovim configuration already exists at $CONFIG_DIR. Skipping setup."
    exit 0
fi

# 6. Setup Configuration and Install Plugins
echo "Cloning LazyVim configuration..."
mkdir -p "${TARGET_HOME}/.config"

# Ensure GitHub is in known_hosts to prevent interactive prompts
mkdir -p "${TARGET_HOME}/.ssh"
chmod 700 "${TARGET_HOME}/.ssh"
ssh-keyscan github.com >>"${TARGET_HOME}/.ssh/known_hosts" 2>/dev/null

# Clone the repository
git clone "${CONFIG_REPO}" "$CONFIG_DIR"

# Clean up .git history so the user can optionally track their own
rm -rf "${CONFIG_DIR}/.git"

# Set correct ownership before running nvim headless sync so it writes to the right paths
chown -R "${TARGET_USER}:${TARGET_USER}" "${TARGET_HOME}/.config" "${TARGET_HOME}/.ssh"

echo "Bootstrapping LazyVim plugins headlessly..."
# Run the plugin sync as the target user to ensure paths (~/.local/share/nvim)
# and permissions are set properly for development.
if [ "${TARGET_USER}" != "root" ]; then
    su - "${TARGET_USER}" -c "nvim --headless '+Lazy! sync' +qa"
else
    nvim --headless '+Lazy! sync' +qa
fi

echo "LazyVim installation and build-time feature setup complete!"
