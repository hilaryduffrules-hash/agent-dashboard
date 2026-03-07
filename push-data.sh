#!/bin/bash
# push-data.sh — Fetch live dashboard data from local API and push to GitHub
# Runs every 5 min via crontab. GitHub Pages serves the result.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
TOKEN_FILE="$HOME/.openclaw/dashboard-auth-token.txt"
GIT_SSH="GIT_SSH_COMMAND=ssh -i $HOME/.ssh/github_openclaw_key -o StrictHostKeyChecking=no"
API_BASE="http://localhost:8888"

# Read auth token
TOKEN=""
if [[ -f "$TOKEN_FILE" ]]; then
    TOKEN=$(cat "$TOKEN_FILE")
fi

AUTH=""
if [[ -n "$TOKEN" ]]; then
    AUTH="?token=$TOKEN"
fi

# Fetch all endpoints
fetch_endpoint() {
    local endpoint="$1"
    local outfile="$2"
    local tmp="${outfile}.tmp"
    if curl -sf --max-time 10 "${API_BASE}${endpoint}${AUTH}" -o "$tmp" 2>/dev/null; then
        if python3 -c "import json,sys; json.load(open('$tmp'))" 2>/dev/null; then
            mv "$tmp" "$outfile"
            return 0
        fi
    fi
    rm -f "$tmp"
    echo "[push-data] WARNING: failed to fetch ${endpoint}" >&2
    return 1
}

cd "$REPO_DIR"

fetch_endpoint "/api/sessions" "data/sessions.json"
fetch_endpoint "/api/agents"   "data/agents.json"
fetch_endpoint "/api/stats"    "data/stats.json"
fetch_endpoint "/api/crons"    "data/crons.json"

# Add metadata file (last-updated timestamp)
echo "{\"updated\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\", \"updatedMs\": $(date +%s)000}" \
    > data/meta.json

# Commit and push if anything changed
if git diff --quiet data/; then
    echo "[push-data] No changes, skipping push"
    exit 0
fi

git add data/
git commit -m "data: $(date -u '+%Y-%m-%d %H:%M UTC')" --quiet

env $GIT_SSH git push origin main --quiet

echo "[push-data] Pushed at $(date)"
