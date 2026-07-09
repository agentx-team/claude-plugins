#!/usr/bin/env bash
# Per-session opt-in markers for the shared notification room. bot-notify has
# exactly one room mode (shared), so unlike bot-chat there is no "global vs
# per-session room" branch and no host-id derivation — every opted-in session
# everywhere resolves to the same room purely via the server-side (botId,
# targetUserId) binding key (session_id is always sent as "" for it, see
# bot-cmd.sh). This file only tracks, per real Claude session id, whether
# THIS session has opted in. No opt-in ⇒ no posting, ever.
#
# Sourced by stop.sh / notify.sh / bot-cmd.sh.
optin_dir() {
  printf '%s/bot-notify/optin' "${XDG_CACHE_HOME:-$HOME/.cache}"
}
optin_marker() { printf '%s/%s' "$(optin_dir)" "$1"; }
optin_add()    { mkdir -p "$(optin_dir)" && : > "$(optin_marker "$1")"; }
optin_remove() { rm -f "$(optin_marker "$1")"; }
optin_has()    { [ -f "$(optin_marker "$1")" ]; }
