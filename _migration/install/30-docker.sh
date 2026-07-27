#!/usr/bin/env bash
#
# 30-docker.sh — Docker CE from Docker's own apt repo, plus the two settings
# that stop the WSL VHD ballooning: log rotation and builder GC.
#
# Native engine in WSL, not Docker Desktop — faster I/O, no licence question,
# and fully scriptable from inside WSL. Requires systemd, which /etc/wsl.conf
# enables (see 90-wsl.sh).
#
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

KEYRING=/etc/apt/keyrings/docker.gpg
SOURCE_LIST=/etc/apt/sources.list.d/docker.list
DAEMON_JSON=/etc/docker/daemon.json

if [[ $DRY_RUN == 1 ]]; then
	warn "would add Docker apt repo, install docker-ce, write $DAEMON_JSON,"
	warn "enable the service, and add $USER to the docker group"
	exit 0
fi

if have docker; then
	ok "docker already installed ($(docker --version))"
else
	log "adding Docker apt repository"
	sudo install -m 0755 -d /etc/apt/keyrings
	curl -fsSL https://download.docker.com/linux/ubuntu/gpg |
		sudo gpg --batch --yes --dearmor -o "$KEYRING"
	sudo chmod a+r "$KEYRING"
	printf 'deb [arch=%s signed-by=%s] https://download.docker.com/linux/ubuntu %s stable\n' \
		"$(dpkg --print-architecture)" "$KEYRING" \
		"$(. /etc/os-release && echo "$VERSION_CODENAME")" |
		sudo tee "$SOURCE_LIST" >/dev/null
	sudo apt-get update -qq
	apt_install docker-ce docker-ce-cli containerd.io \
		docker-buildx-plugin docker-compose-plugin
fi

log "writing $DAEMON_JSON"
sudo mkdir -p /etc/docker

daemon_json_tmp="$(mktemp)"
trap 'rm -f "$daemon_json_tmp"' EXIT
cat >"$daemon_json_tmp" <<'EOF'
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "builder": {
    "gc": {
      "enabled": true,
      "defaultKeepStorage": "10GB"
    }
  }
}
EOF

if [[ -f $DAEMON_JSON ]] && sudo cmp -s "$daemon_json_tmp" "$DAEMON_JSON"; then
	ok "$DAEMON_JSON already up to date"
else
	if [[ -f $DAEMON_JSON ]]; then
		sudo cp -a "$DAEMON_JSON" "${DAEMON_JSON}.bak"
		warn "backed up existing daemon.json -> ${DAEMON_JSON}.bak"
	fi
	sudo install -m 0644 "$daemon_json_tmp" "$DAEMON_JSON"
fi

rm -f "$daemon_json_tmp"
trap - EXIT

log "enabling docker service"
sudo systemctl enable --now docker
sudo systemctl restart docker

if id -nG "$USER" | tr ' ' '\n' | grep -qx docker; then
	ok "$USER already in the docker group"
else
	log "adding $USER to the docker group"
	sudo usermod -aG docker "$USER"
	warn "group change applies on next new session (or: wsl --shutdown)"
fi
