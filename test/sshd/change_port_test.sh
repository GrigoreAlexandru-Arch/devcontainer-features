#!/bin/bash
set -e

# Import the test framework library
source dev-container-features-test-lib

# 1. Verify the necessary packages were installed
check "sshd binary exists" command -v sshd
check "ssh-keygen binary exists" command -v ssh-keygen

# 2. Verify the configuration files were placed correctly
check "sshd_config.d file exists" test -f /etc/ssh/sshd_config.d/devcontainer.conf
check "startup helper script exists" test -x /usr/local/share/devcontainer-sshd/start-sshd.sh

# 3. Verify user and authorized_keys setup
check ".ssh directory exists" test -d /home/vscode/.ssh
check "authorized_keys exists" test -f /home/vscode/.ssh/authorized_keys

# --- SSH Connectivity Test (Using Pre-existing Key) ---

# 4. Start the SSH daemon in the background
/usr/local/share/devcontainer-sshd/start-sshd.sh

# 5. Locate the private key placed next to this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PRIVATE_KEY_PATH="${SCRIPT_DIR}/dummy_key"

check "private key exists in test directory" test -f "${PRIVATE_KEY_PATH}"

# 6. Secure the private key
# SSH requires private keys to have restrictive permissions.
# We copy it to /tmp to avoid modifying the permissions of your local source files.
cp "${PRIVATE_KEY_PATH}" /tmp/dummy_key
chmod 600 /tmp/dummy_key
chown vscode:vscode /tmp/dummy_key

# 7. Attempt an SSH connection to localhost as the vscode user
check "ssh connection to localhost succeeds" \
    ssh -p 2222 -i /tmp/dummy_key \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    vscode@localhost "echo 'SSH_SUCCESS'" | grep -q 'SSH_SUCCESS'

# Report results
reportResults
