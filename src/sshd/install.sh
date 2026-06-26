#!/usr/bin/env bash

set -euo pipefail

AUTHORIZED_KEYS="${AUTHORIZEDKEYS:-}"
LOGIN_USER="${USER:-automatic}"
SSH_PORT="${SSHPORT:-22}"

#
# Validate the SSH port to prevent configuration issues
#
if ! [[ "${SSH_PORT}" =~ ^[0-9]+$ ]] || [ "${SSH_PORT}" -lt 1 ] || [ "${SSH_PORT}" -gt 65535 ]; then
    echo "ERROR: Invalid SSH port specified: '${SSH_PORT}'. Must be an integer between 1 and 65535."
    exit 1
fi

echo "Installing OpenSSH server..."

export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y --no-install-recommends \
    openssh-server \
    openssh-client

rm -rf /var/lib/apt/lists/*

mkdir -p /var/run/sshd

#
# Determine login user
#
if [ "${LOGIN_USER}" = "automatic" ]; then
    if [ -n "${_REMOTE_USER:-}" ]; then
        LOGIN_USER="${_REMOTE_USER}"
    else
        LOGIN_USER="$(id -un 1000 2>/dev/null || true)"
    fi
fi

if ! id "${LOGIN_USER}" >/dev/null 2>&1; then
    echo "User '${LOGIN_USER}' does not exist."
    exit 1
fi

HOME_DIR="$(getent passwd "${LOGIN_USER}" | cut -d: -f6)"

echo "Using login user: ${LOGIN_USER}"
echo "Home directory: ${HOME_DIR}"
echo "Using SSH port: ${SSH_PORT}"

mkdir -p "${HOME_DIR}/.ssh"

#
# Authorized keys - Strict explicit list
#
if [ -n "${AUTHORIZED_KEYS}" ]; then
    echo "Using explicit authorized keys."
    printf '%s\n' "${AUTHORIZED_KEYS}" >"${HOME_DIR}/.ssh/authorized_keys"
else
    echo "ERROR: No authorized keys provided."
    exit 1
fi

chmod 700 "${HOME_DIR}/.ssh"
chmod 600 "${HOME_DIR}/.ssh/authorized_keys"

chown -R "${LOGIN_USER}:${LOGIN_USER}" \
    "${HOME_DIR}/.ssh"

#
# Clean up default SSH configurations so they do not conflict with our custom port
#
if [ -f /etc/ssh/sshd_config ]; then
    # Comment out any existing non-commented "Port" directives in the default sshd_config
    sed -i -E 's/^\s*Port\s+/#\0/g' /etc/ssh/sshd_config
fi

#
# SSHD configuration
#
mkdir -p /etc/ssh/sshd_config.d

cat >/etc/ssh/sshd_config.d/devcontainer.conf <<EOF
# --- Network ---
Port ${SSH_PORT}

# --- Authentication ---
PasswordAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys
PermitRootLogin no
PermitEmptyPasswords no

# --- Session Management ---
MaxAuthTries 3
MaxSessions 10
ClientAliveInterval 300
ClientAliveCountMax 2

# --- Forwarding ---
# Note: Agent/TCP forwarding carry lateral movement risks if the container is compromised, 
# but are kept 'yes' as they are core features of this devcontainer extension.
AllowAgentForwarding yes
AllowTcpForwarding yes
X11Forwarding no

# --- Logging ---
# VERBOSE logs the key fingerprint of the key used for login, which is crucial for auditing.
LogLevel VERBOSE

# --- Cryptography (Strict Modern Standards) ---
KexAlgorithms curve25519-sha256@libssh.org,curve25519-sha256,diffie-hellman-group16-sha512,diffie-hellman-group18-sha512,diffie-hellman-group-exchange-sha256
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr,aes192-ctr,aes128-ctr
MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com,umac-128-etm@openssh.com

UsePAM yes
EOF

#
# Startup helper
#
mkdir -p /usr/local/share/devcontainer-sshd

cat >/usr/local/share/devcontainer-sshd/start-sshd.sh <<'EOF'
#!/usr/bin/env bash

sudo ssh-keygen -A

if ! pgrep -x sshd; then
    echo "Starting sshd..."
    sudo /usr/sbin/sshd
fi
EOF

chmod +x /usr/local/share/devcontainer-sshd/start-sshd.sh

echo
echo "Authorized key fingerprints:"
ssh-keygen -lf "${HOME_DIR}/.ssh/authorized_keys"
echo
echo "SSH feature installation complete."
