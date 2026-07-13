#!/bin/bash
# Claude Code PreToolUse hook (Bash): guard live-cluster and live-deploy actions.
# This studio stages all deploys for human sign-off — it never applies them live.
# If a command tries to mutate a live cluster or push images, warn loudly. The
# hard block also lives in settings.json `deny`; this is defense-in-depth + a
# clear message. Exit 0 (non-blocking message); settings.json deny does the stop.

INPUT=$(cat)

if command -v jq >/dev/null 2>&1; then
    CMD=$(echo "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null)
else
    CMD=$(echo "$INPUT" | grep -oE '"command"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"command"[[:space:]]*:[[:space:]]*"//;s/"$//')
fi

case "$CMD" in
    *"helm upgrade"*|*"helm install"*|*"helm uninstall"*|*"helm rollback"*|*"kubectl apply"*|*"kubectl delete"*|*"kubectl edit"*|*"docker push"*|*"git push"*)
        echo "[validate-push] '$CMD'" >&2
        echo "[validate-push] Live deploys / pushes are staged for human sign-off in dev-studio." >&2
        echo "[validate-push] Write the command into the deploy-plan instead; an operator runs it." >&2
        ;;
esac
exit 0
