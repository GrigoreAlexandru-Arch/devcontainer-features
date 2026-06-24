#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

# Import the devcontainer CLI test library
source dev-container-features-test-lib

echo "Running tests for sshd feature (key_list_test scenario)..."

AUTH_KEYS_FILE="${HOME}/.ssh/authorized_keys"

# 1. Verify Installation & Basic Permissions
check "openssh-server is installed" dpkg -s openssh-server >/dev/null
check "startup helper exists and is executable" test -x /usr/local/share/devcontainer-sshd/start-sshd.sh
check ".ssh directory permissions are 700" [ "$(stat -c %a "${HOME}/.ssh")" = "700" ]
check "authorized_keys permissions are 600" [ "$(stat -c %a "${AUTH_KEYS_FILE}")" = "600" ]

# 2. Verify Key Injection from scenarios.json
check "contains test-key-1" grep -q "test-key-1" "${AUTH_KEYS_FILE}"
check "authorized_keys has exactly 2 lines" [ "$(wc -l <"${AUTH_KEYS_FILE}")" -eq 2 ]

# ==========================================
# 3. END-TO-END CONNECTION TEST
# ==========================================

# Start the SSH daemon (test environments don't always trigger the postStartCommand)
echo "Starting SSH daemon for E2E test..."
sudo /usr/local/share/devcontainer-sshd/start-sshd.sh

# Generate a temporary, password-less SSH key specifically for this test
echo "Generating temporary SSH key..."
ssh-keygen -t ed25519 -f /tmp/test_ssh_key -N "" -q

# Append the test public key so we are authorized to connect
cat /tmp/test_ssh_key.pub >>"${AUTH_KEYS_FILE}"

# Attempt to SSH into localhost and run a simple echo command.
# We bypass StrictHostKeyChecking so the test doesn't hang waiting for a user to type "yes".
echo "Attempting live SSH connection..."
check "can connect via ssh to localhost" ssh -i /tmp/test_ssh_key \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -o BatchMode=yes \
    "$(whoami)@localhost" "echo 'Successfully connected over SSH!'"

# Report results
reportResults
