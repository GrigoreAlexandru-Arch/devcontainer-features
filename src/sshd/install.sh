#!/usr/bin/env bash

set -euo pipefail

AUTHORIZED_KEYS="${AUTHORIZEDKEYS:-}"
LOGIN_USER="${USER:-automatic}"

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
    elif id vscode >/dev/null 2>&1; then
        LOGIN_USER="vscode"
    elif id node >/dev/null 2>&1; then
        LOGIN_USER="node"
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
# SSHD configuration
#
mkdir -p /etc/ssh/sshd_config.d

cat >/etc/ssh/sshd_config.d/devcontainer.conf <<EOF
PasswordAuthentication no
KbdInteractiveAuthentication no
ChallengeResponseAuthentication no

PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys

AllowAgentForwarding yes
AllowTcpForwarding yes

PermitRootLogin no

X11Forwarding no

UsePAM yes
EOF

#
# Host keys
#
sudo ssh-keygen -A

#
# Startup helper
#
mkdir -p /usr/local/share/devcontainer-sshd

cat >/usr/local/share/devcontainer-sshd/start-sshd.sh <<'EOF'
#!/usr/bin/env bash

sudo ssh-keygen -A >/dev/null 2>&1

if ! pgrep -x sshd >/dev/null 2>&1; then
    echo "Starting sshd..."
    sudo /usr/sbin/sshd
fi
EOF

chmod +x /usr/local/share/devcontainer-sshd/start-sshd.sh

echo
echo "Authorized key fingerprints:"
ssh-keygen -lf "${HOME_DIR}/.ssh/authorized_keys" || true
echo
echo "SSH feature installation complete."
