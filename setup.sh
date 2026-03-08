#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_SCRIPT="${ROOT_DIR}/codeflare.sh"
TARGET_DIR="${HOME}/.local/bin"
TARGET_BIN="${TARGET_DIR}/codeflare"
CONFIG_DIR="${HOME}/.config/codeflare"
CONFIG_FILE="${CONFIG_DIR}/.env"
NO_REMOTE_VALIDATE="false"

for arg in "$@"; do
  case "$arg" in
    --no-validate-remote)
      NO_REMOTE_VALIDATE="true"
      ;;
    -h|--help)
      echo "Usage: ./setup.sh [--no-validate-remote]"
      exit 0
      ;;
    *)
      echo "Unknown argument: $arg" >&2
      echo "Usage: ./setup.sh [--no-validate-remote]" >&2
      exit 1
      ;;
  esac
done

require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Missing required command: $cmd" >&2
    exit 1
  fi
}

read_env_var() {
  local key="$1"
  local file="$2"
  local line
  line="$(grep -E "^[[:space:]]*${key}=" "$file" | tail -n 1 || true)"
  if [[ -z "$line" ]]; then
    return 1
  fi
  line="${line#*=}"
  line="$(printf '%s' "$line" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
  if [[ "$line" =~ ^\".*\"$ || "$line" =~ ^\'.*\'$ ]]; then
    line="${line:1:${#line}-2}"
  fi
  printf '%s' "$line"
}

valid_port() {
  local p="$1"
  [[ "$p" =~ ^[0-9]+$ ]] || return 1
  (( p >= 1 && p <= 65535 ))
}

valid_hostname() {
  local h="$1"
  [[ "$h" =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?)+$ ]]
}

echo "==> Checking prerequisites"
require_cmd bash
require_cmd cp
require_cmd chmod
require_cmd mkdir
require_cmd opencode
require_cmd cloudflared

if [[ ! -f "$SOURCE_SCRIPT" ]]; then
  echo "Missing required source script: $SOURCE_SCRIPT" >&2
  exit 1
fi

echo "==> Preparing config"
mkdir -p "$CONFIG_DIR"
if [[ ! -f "$CONFIG_FILE" ]]; then
  umask 077
  if [[ -f "${ROOT_DIR}/.env" ]]; then
    cp "${ROOT_DIR}/.env" "$CONFIG_FILE"
  else
    cp "${ROOT_DIR}/.env.example" "$CONFIG_FILE"
  fi
  echo "Created ${CONFIG_FILE}"
fi
chmod 600 "$CONFIG_FILE"

echo "==> Installing codeflare command"
mkdir -p "$TARGET_DIR"
cp "$SOURCE_SCRIPT" "$TARGET_BIN"
chmod +x "$TARGET_BIN"

# Validate config values safely without sourcing executable shell
hostname="$(read_env_var OPENCODE_PUBLIC_HOSTNAME "$CONFIG_FILE" || true)"
port="$(read_env_var OPENCODE_PORT "$CONFIG_FILE" || true)"
tunnel_id="$(read_env_var CLOUDFLARED_TUNNEL_ID "$CONFIG_FILE" || true)"
creds="$(read_env_var CLOUDFLARED_CREDENTIALS_PATH "$CONFIG_FILE" || true)"

if [[ -z "$hostname" ]]; then
  echo "OPENCODE_PUBLIC_HOSTNAME is required in ${CONFIG_FILE}" >&2
  exit 1
fi
if ! valid_hostname "$hostname"; then
  echo "OPENCODE_PUBLIC_HOSTNAME is invalid: $hostname" >&2
  exit 1
fi
if [[ -z "$port" ]] || ! valid_port "$port"; then
  echo "OPENCODE_PORT must be an integer between 1 and 65535 in ${CONFIG_FILE}" >&2
  exit 1
fi

if [[ -z "$tunnel_id" && -n "$creds" ]]; then
  inferred="$(basename "$creds" .json)"
  if [[ "$inferred" =~ ^[0-9a-fA-F-]{36}$ ]]; then
    tunnel_id="$inferred"
  fi
fi
if [[ -z "$tunnel_id" ]]; then
  echo "CLOUDFLARED_TUNNEL_ID missing and not inferable from CLOUDFLARED_CREDENTIALS_PATH in ${CONFIG_FILE}" >&2
  exit 1
fi

if [[ -z "$creds" ]]; then
  creds="$HOME/.cloudflared/${tunnel_id}.json"
fi
if [[ ! -f "$creds" ]]; then
  echo "CLOUDFLARED_CREDENTIALS_PATH file not found: $creds" >&2
  exit 1
fi

if [[ "$NO_REMOTE_VALIDATE" != "true" ]]; then
  if ! cloudflared tunnel info "$tunnel_id" >/dev/null 2>&1; then
    echo "Tunnel ID not found or inaccessible: $tunnel_id" >&2
    exit 1
  fi
else
  echo "Skipping remote tunnel validation (--no-validate-remote)"
fi

echo "Installed: $TARGET_BIN"
if [[ ":$PATH:" != *":$TARGET_DIR:"* ]]; then
  shell_name="$(basename "${SHELL:-}")"
  profile_file="~/.profile"
  profile_cmd="export PATH=\"$TARGET_DIR:\$PATH\""
  profile_append_cmd="echo 'export PATH=\"$TARGET_DIR:\$PATH\"' >> ~/.profile"
  if [[ "$shell_name" == "zsh" ]]; then
    profile_file="~/.zshrc"
    profile_append_cmd="echo 'export PATH=\"$TARGET_DIR:\$PATH\"' >> ~/.zshrc"
  elif [[ "$shell_name" == "bash" ]]; then
    profile_file="~/.bashrc"
    profile_append_cmd="echo 'export PATH=\"$TARGET_DIR:\$PATH\"' >> ~/.bashrc"
  elif [[ "$shell_name" == "fish" ]]; then
    profile_file="~/.config/fish/config.fish"
    profile_cmd="set -gx PATH $TARGET_DIR \$PATH"
    profile_append_cmd="echo 'set -gx PATH $TARGET_DIR \$PATH' >> ~/.config/fish/config.fish"
  fi

  echo
  echo "Add this to your shell profile ($profile_file):"
  echo "  $profile_cmd"
  echo "Or append it automatically:"
  echo "  $profile_append_cmd"
  echo "Or run for current shell now:"
  echo "  export PATH=\"$TARGET_DIR:\$PATH\""
fi

echo
echo "Next steps:"
echo "1) Edit ${CONFIG_FILE} if needed"
echo "2) Run from any project dir: codeflare"
