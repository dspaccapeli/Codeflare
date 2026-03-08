# Codeflare

Run OpenCode from any local project and publish it on your domain through Cloudflare Tunnel.

## What you get

- One command to run local OpenCode + Cloudflare tunnel.
- Stable public URL (for example `code.example.com`).
- Access control handled by Cloudflare Access.

## Prerequisites

- `opencode` installed
- `cloudflared` installed
- A domain in Cloudflare (for example `example.com`)

## 1) Clone and install the command

```bash
git clone <repo-url>
cd <repo-directory>
./setup.sh
```

This installs `codeflare` to `~/.local/bin/codeflare`.
The source file in this repo is `codeflare.sh` (edit that, then re-run `./setup.sh`).

## 2) Create and fill `.env` (required)

`setup.sh` creates this file automatically if missing:

- `~/.config/codeflare/.env`

Start from the generated file (or from `.env.example` if you prefer manual setup), then fill:

- `CLOUDFLARED_TUNNEL_ID=<your tunnel id>`
- `CLOUDFLARED_CREDENTIALS_PATH=/Users/<you>/.cloudflared/<tunnel-id>.json`
- `OPENCODE_PUBLIC_HOSTNAME=code.example.com`
- `OPENCODE_LISTEN_HOST=127.0.0.1`
- `OPENCODE_PORT=4096`

Without this file, `codeflare` will exit with a config error.

## 3) Configure Cloudflare (first time only)

### Create a tunnel and credentials

```bash
cloudflared tunnel login
cloudflared tunnel create opencode
cloudflared tunnel list
```

Copy the new tunnel ID from `cloudflared tunnel list`.

### Create DNS route for your OpenCode hostname

Example:

```bash
cloudflared tunnel route dns <TUNNEL_ID> code.example.com
```

### Create an Access application

In Cloudflare Zero Trust:

1. Go to `Access` -> `Applications` -> `Add an application` -> `Self-hosted`.
2. Add public hostname `code.example.com` (use your real hostname).
3. Add at least one `Allow` policy (for example your email).
4. Save.

## 4) Validate and run

```bash
codeflare check
codeflare /path/to/project
```

Open:

- `https://code.example.com`

Important:

1. Configure Cloudflare Access for your public hostname so the endpoint is protected.
2. `opencode web` opens a local browser tab automatically; it is safe to close that tab.

## Commands

- `codeflare` or `codeflare up [PROJECT_DIR]`: run OpenCode + tunnel
- `codeflare local [PROJECT_DIR]`: run only OpenCode
- `codeflare tunnel`: run only tunnel (OpenCode already running)
- `codeflare dns`: force DNS route update for hostname -> tunnel
- `codeflare check`: validate dependencies and config

## Troubleshooting

- `Missing env file`: run `./setup.sh` again.
- `Tunnel ID not found`: verify `CLOUDFLARED_TUNNEL_ID` and your Cloudflare login (`cloudflared tunnel list`).
- `Host already exists` on DNS route: `codeflare` already uses overwrite mode for DNS updates.

## Optional log noise filter

If you want to hide harmless Cloudflare disconnect messages (`canceled by remote with error code 0`), set:

```bash
CODEFLARE_QUIET_DISCONNECT_LOGS=true
```

in `~/.config/codeflare/.env`.

## Optional DNS overwrite mode

By default, `codeflare` does not force-overwrite an existing DNS record.
To force replacement on each run:

```bash
CODEFLARE_FORCE_DNS=true
```
