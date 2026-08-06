#!/usr/bin/env bash
#
# 35-azure.sh — Azure CLI from Microsoft's own apt repo.
#
# Not from noble's own archive: Ubuntu does not ship azure-cli at all, and the
# pip/pipx route pulls a large dependency tree into a venv that then shadows the
# distro's python bindings. Microsoft's repo is the supported path and tracks
# releases closely (2.89 at time of writing).
#
# Why it is here at all: no portal script invokes `az` directly — ./scripts/
# fetch-secrets talks to the Key Vault REST API with jq + curl. It is a manual
# tool for poking at Key Vault, ACR, and app services by hand, and it was on the
# old box, so a rebuild that omits it is a rebuild that surprises you later.
#
# Follows the same keyring + sources.list shape as 30-docker.sh.
#
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

KEYRING=/etc/apt/keyrings/microsoft.gpg
SOURCE_LIST=/etc/apt/sources.list.d/azure-cli.list

if [[ $DRY_RUN == 1 ]]; then
	warn "would add the Microsoft apt repo and install azure-cli"
	exit 0
fi

if have az; then
	ok "azure-cli already installed ($(az version --output tsv 2>/dev/null | head -1 || echo present))"
	exit 0
fi

log "adding the Microsoft apt repository"
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://packages.microsoft.com/keys/microsoft.asc |
	sudo gpg --batch --yes --dearmor -o "$KEYRING"
sudo chmod a+r "$KEYRING"

# The repo is published per Ubuntu codename; noble is present. Fall back to
# jammy if a newer codename has not been published yet — azure-cli is a pure
# Python package and the jammy build runs fine on a later release.
codename="$(. /etc/os-release && echo "$VERSION_CODENAME")"
if ! curl -fsSL -o /dev/null "https://packages.microsoft.com/repos/azure-cli/dists/$codename/Release"; then
	warn "no azure-cli repo for '$codename' — falling back to jammy"
	codename=jammy
fi

printf 'deb [arch=%s signed-by=%s] https://packages.microsoft.com/repos/azure-cli/ %s main\n' \
	"$(dpkg --print-architecture)" "$KEYRING" "$codename" |
	sudo tee "$SOURCE_LIST" >/dev/null

sudo apt-get update -qq
apt_install azure-cli

have az || die "az not on PATH after install"
ok "azure-cli $(az version --output tsv 2>/dev/null | head -1 || echo installed)"
warn "run \`az login\` to authenticate (nothing is carried over from the old box)"
