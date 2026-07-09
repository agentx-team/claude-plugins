#!/usr/bin/env bash
# Shared helper: when BOT_GLOBAL_ROOM_NAME is set, every Claude Code session on
# this machine funnels into ONE Matrix room instead of per-session rooms. The
# global session id is derived deterministically from the room name + this
# host's primary private (LAN) IP, so:
#   - all sessions on the same host resolve to the SAME id  → same room
#   - different hosts get different ids                      → no collisions
# The server API is unchanged; this is just a stable session_id the client
# reuses. Printed as "gbl-<32 hex chars>". Prints nothing when the feature is off.
#
# Sourced by session-start.sh / stop.sh / bot-cmd.sh; also runnable standalone.

# host_lan_ip echoes the primary private IPv4/IPv6 (best-effort, deterministic).
# Order: RFC1918 IPv4 → ULA IPv6 (fd00::/8) → hostname → "localhost". Never the
# loopback or a public address (those would be unstable / privacy-leaking).
host_lan_ip() {
  local ip=""
  # Linux: `ip` gives the source addr used to reach a private target.
  if command -v ip >/dev/null 2>&1; then
    ip=$(ip -o route get 10.0.0.1 2>/dev/null | grep -oE 'src [0-9a-fA-F:.]+' | awk '{print $2}')
    [ -z "$ip" ] && ip=$(ip -o -4 addr show scope global 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -1)
    [ -z "$ip" ] && ip=$(ip -o -6 addr show scope global 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | grep -Ei '^(fd|fc)' | head -1)
  fi
  # macOS / fallback.
  if [ -z "$ip" ] && command -v ifconfig >/dev/null 2>&1; then
    ip=$(ifconfig 2>/dev/null | grep -oE 'inet (10|172\.(1[6-9]|2[0-9]|3[01])|192\.168)\.[0-9.]+' | awk '{print $2}' | head -1)
  fi
  [ -z "$ip" ] && ip=$(hostname 2>/dev/null)
  [ -z "$ip" ] && ip="localhost"
  printf '%s' "$ip"
}

# sha256_hex echoes the hex sha256 of stdin, portable across coreutils/openssl.
sha256_hex() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum | awk '{print $1}'
  else
    shasum -a 256 | awk '{print $1}'
  fi
}

# global_session_id prints the deterministic id, or nothing if the feature off.
global_session_id() {
  [ -z "${BOT_GLOBAL_ROOM_NAME:-}" ] && return 0
  local seed hash
  seed="${BOT_GLOBAL_ROOM_NAME}@$(host_lan_ip)"
  hash=$(printf '%s' "$seed" | sha256_hex | cut -c1-32)
  printf 'gbl-%s' "$hash"
}

# ── Per-session opt-in (global mode) ────────────────────────────────────────
# In global mode every session shares ONE room, but a session only posts after
# it explicitly runs /bot — exactly like the default per-room mode. Opt-in is a
# marker file keyed by the REAL Claude session id (so concurrent sessions in the
# same working directory are tracked independently). No opt-in ⇒ no posting.
optin_dir() {
  printf '%s/bot-chat/optin' "${XDG_CACHE_HOME:-$HOME/.cache}"
}
optin_marker() { printf '%s/%s' "$(optin_dir)" "$1"; }
optin_add()    { mkdir -p "$(optin_dir)" && : > "$(optin_marker "$1")"; }
optin_remove() { rm -f "$(optin_marker "$1")"; }
optin_has()    { [ -f "$(optin_marker "$1")" ]; }

# Standalone: print the id (empty line when off).
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  global_session_id
  echo
fi
