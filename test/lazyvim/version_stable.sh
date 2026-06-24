#!/bin/bash
set -e

source dev-container-features-test-lib

echo "Running tests for the LazyVim feature..."

# 1. Verify Core Binaries
check "neovim is installed" nvim --version
check "git is installed" git --version

# 2. Verify System Dependencies (Required for Telescope/Clipboard)
check "ripgrep is installed" which rg
# Note: On Ubuntu/Debian, the fd-find package installs the binary as 'fdfind'
check "fd is installed" which fdfind
check "xclip is installed" which xclip

# 3. Verify Configuration Cloning
check "lazyvim config directory exists" bash -c "ls -la ~/.config/nvim/init.lua"

# 4. Verify Headless Bootstrapping Succeeded
# If the headless step in install.sh failed, this directory won't exist
check "lazy.nvim package manager is bootstrapped" bash -c "ls -d ~/.local/share/nvim/lazy/lazy.nvim"

# 5. Verify Editor Stability
# This runs Neovim headlessly and quits immediately. If there are missing
# runtime dependencies or Lua syntax errors, this command will fail.
check "neovim launches cleanly without errors" nvim --headless +qa

# Report results to the Devcontainer CLI
reportResults
