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
    # Matches both current (nvim-linux-x86_64) and legacy (nvim-linux64) naming
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

# 4. Fetch the specific Download URL via the GitHub API
echo "Querying GitHub API for Neovim release: ${NVIM_VERSION}..."

# We extract all download URLs and use grep to find the one matching our architecture
DOWNLOAD_URL=$(curl -s "$API_URL" | jq -r '.assets[].browser_download_url' | grep -E "$ASSET_PATTERN" | head -n 1)

if [ -z "$DOWNLOAD_URL" ]; then
    echo "Error: Could not find a valid Neovim asset for architecture $ARCH in release ${NVIM_VERSION}."
    exit 1
fi

echo "Downloading Neovim from: $DOWNLOAD_URL"

# The -f flag ensures curl fails if the URL is unreachable
curl -LO -f "$DOWNLOAD_URL"

# Extract the filename from the URL
FILENAME=$(basename "$DOWNLOAD_URL")

# 5. Extract and Symlink dynamically
tar -C /opt -xzf "$FILENAME"
rm "$FILENAME"

# Dynamically find the extracted folder (avoids hardcoding folder names)
EXTRACTED_DIR=$(find /opt -maxdepth 1 -name "nvim-linux*" -type d | head -n 1)

if [ -z "$EXTRACTED_DIR" ]; then
    echo "Error: Failed to find extracted Neovim directory in /opt."
    exit 1
fi

ln -s "${EXTRACTED_DIR}/bin/nvim" /usr/local/bin/nvim

# 6. Determine the target user and home directory
if [ "${_REMOTE_USER}" = "root" ] || [ -z "${_REMOTE_USER}" ]; then
    TARGET_USER="root"
    TARGET_HOME="/root"
else
    TARGET_USER="${_REMOTE_USER}"
    TARGET_HOME="${_REMOTE_USER_HOME:-/home/${TARGET_USER}}"
fi

echo "Setting up LazyVim for user: ${TARGET_USER} at ${TARGET_HOME}"

# 7. Clone the LazyVim repository
mkdir -p "${TARGET_HOME}/.config"
git clone "${CONFIG_REPO}" "${TARGET_HOME}/.config/nvim"

# Remove the .git folder so the user isn't stuck inside the starter repo history
rm -rf "${TARGET_HOME}/.config/nvim/.git"

# Ensure the target user owns the configuration directory
chown -R "${TARGET_USER}:${TARGET_USER}" "${TARGET_HOME}/.config/nvim"

# 8. Headless Bootstrapping
echo "Bootstrapping LazyVim plugins headlessly..."
su - "${TARGET_USER}" -c "nvim --headless '+Lazy! sync' +qa"

echo "LazyVim installation complete!"
