#!/usr/bin/env bash
set -e

# Fetch options from devcontainer-feature.json
NVIM_VERSION=${VERSION:-"stable"}
CONFIG_REPO=${CONFIGREPO:-"https://github.com/LazyVim/starter"}

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

# 2. Determine Architecture
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
    # win32yank releases are primarily x86/x64; we'll skip it on ARM later
else
    echo "Unsupported architecture: $ARCH"
    exit 1
fi

# 3. Determine the GitHub API Endpoint for Neovim
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

# 5. Install External Binaries (FZF, Tree-Sitter, Win32Yank)
echo "Installing external binaries..."

# Download and setup fzf
echo "Fetching latest fzf release..."
FZF_LATEST_URL=$(curl -s https://api.github.com/repos/junegunn/fzf/releases/latest | jq -r ".assets[].browser_download_url" | grep "linux_${FZF_ARCH}\.tar\.gz")
curl -LO -f "$FZF_LATEST_URL"
tar -xzf $(basename "$FZF_LATEST_URL")
mv fzf /usr/local/bin/
rm $(basename "$FZF_LATEST_URL")

# Download and setup tree-sitter-cli
echo "Fetching latest tree-sitter release..."
TS_LATEST_URL=$(curl -s https://api.github.com/repos/tree-sitter/tree-sitter/releases/latest | jq -r ".assets[].browser_download_url" | grep "tree-sitter-linux-${TS_ARCH}\.gz")
curl -LO -f "$TS_LATEST_URL"
gzip -d $(basename "$TS_LATEST_URL")
chmod +x "tree-sitter-linux-${TS_ARCH}"
mv "tree-sitter-linux-${TS_ARCH}" /usr/local/bin/tree-sitter

# Download and setup win32yank (for WSL clipboard integration)
if [ "$ARCH" = "x86_64" ]; then
    echo "Fetching win32yank for WSL clipboard support..."
    WIN32YANK_URL=$(curl -s https://api.github.com/repos/equalsraf/win32yank/releases/latest | jq -r ".assets[].browser_download_url" | grep "${WIN32YANK_ARCH}\.zip")
    curl -LO -f "$WIN32YANK_URL"
    unzip -q -o $(basename "$WIN32YANK_URL") -d win32yank-tmp
    chmod +x win32yank-tmp/win32yank.exe
    mv win32yank-tmp/win32yank.exe /usr/local/bin/win32yank.exe
    rm -rf win32yank-tmp $(basename "$WIN32YANK_URL")
else
    echo "Skipping win32yank (not officially published for $ARCH)."
fi

# 6. Determine Target User and Home Directory for Build Time
TARGET_USER=${_REMOTE_USER:-"root"}
TARGET_HOME=${_REMOTE_USER_HOME:-$HOME}
CONFIG_DIR="${TARGET_HOME}/.config/nvim"

echo "Targeting user: ${TARGET_USER} with home: ${TARGET_HOME}"

if [ -d "$CONFIG_DIR" ]; then
    echo "Neovim configuration already exists at $CONFIG_DIR. Skipping setup."
    exit 0
fi

# 7. Setup Configuration and Install Plugins
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
    su - "${TARGET_USER}" -c "rm -rf ${CONFIG_DIR}/.git"
else
    git clone "${CONFIG_REPO}" "$CONFIG_DIR"
    rm -rf "${CONFIG_DIR}/.git"
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
