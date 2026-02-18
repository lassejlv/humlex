#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

DEFAULT_REPO="vercel-labs/agent-skills"

usage() {
    cat <<'USAGE'
Usage:
  ./skills.sh <skills-command> [args...]
  ./skills.sh bootstrap [repo]

Examples:
  ./skills.sh add vercel-labs/agent-skills
  ./skills.sh list
  ./skills.sh check
  ./skills.sh update
  ./skills.sh bootstrap
USAGE
}

run_skills() {
    if command -v skills >/dev/null 2>&1; then
        skills "$@"
        return
    fi

    if command -v npx >/dev/null 2>&1; then
        npx --yes skills "$@"
        return
    fi

    echo "Error: skills CLI not found and npx is unavailable." >&2
    echo "Install Node.js/npm first, or install skills globally." >&2
    exit 1
}

if [ $# -eq 0 ]; then
    usage
    exit 0
fi

command_name="$1"
shift

case "${command_name}" in
    -h|--help|help)
        usage
        ;;
    bootstrap)
        repo="${1:-${DEFAULT_REPO}}"
        run_skills add "${repo}" --agent codex
        ;;
    *)
        run_skills "${command_name}" "$@"
        ;;
esac
