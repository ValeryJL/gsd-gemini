#!/bin/bash
# Agent selector/dispatcher
# Routes agent execution to the appropriate backend (groq, gemini, github)

set -e

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)

# Load environment variables
if [ -f "$SCRIPT_DIR/.env" ]; then
    export $(grep -v '^#' "$SCRIPT_DIR/.env" | xargs)
fi

# Default to groq if not specified
: "${AGENT_BACKEND:=groq}"

# Agent role and task
AGENT_ROLE="$1"
TASK_DESC="$2"
DEBUG_FLAG="$3"

if [ -z "$AGENT_ROLE" ] || [ -z "$TASK_DESC" ]; then
    echo "{\"error\":\"Usage: agent-dispatcher <role> <task> [--debug]\"}"
    exit 1
fi

# Route to appropriate backend
case "$AGENT_BACKEND" in
    groq)
        source "$SCRIPT_DIR/agents/groq/groq-simple-agent.sh"
        call_groq_agent "$TASK_DESC" 15
        ;;
    gemini)
        # TODO: implement gemini backend
        echo "Gemini backend not yet implemented" >&2
        exit 1
        ;;
    github)
        # TODO: implement github models backend
        echo "GitHub Models backend not yet implemented" >&2
        exit 1
        ;;
    *)
        echo "Unknown agent backend: $AGENT_BACKEND" >&2
        exit 1
        ;;
esac
