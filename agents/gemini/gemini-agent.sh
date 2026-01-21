#!/bin/bash
# Gemini CLI Agent Executor
# Integrates with Google's Gemini CLI for agent execution

set -e

# Load environment variables
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
if [ -f "$SCRIPT_DIR/.env" ]; then
    export $(grep -v '^#' "$SCRIPT_DIR/.env" | xargs)
fi

# Defaults for Gemini
: "${GEMINI_CLI_PATH:=gemini}"
: "${GEMINI_MODEL:=gemini-2.5-flash}"
: "${GEMINI_TEMPERATURE:=0.4}"
: "${GEMINI_MAX_TOKENS:=2000}"

# Execute task using Gemini CLI
call_gemini_agent() {
    local task_prompt="$1"
    local max_iterations=${2:-15}
    
    for iteration in $(seq 1 $max_iterations); do
        echo "[Iteration $iteration]" >&2
        
        # Call Gemini CLI
        local response=$("$GEMINI_CLI_PATH" -p "$task_prompt" --output-format json 2>&1)
        
        # Check for errors
        if echo "$response" | grep -q "error\|Error"; then
            echo "Gemini error: $response" >&2
            exit 1
        fi
        
        # Extract content from response
        local content=$(echo "$response" | jq -r '.response // .content // .' 2>/dev/null)
        
        if [ -z "$content" ]; then
            echo "Error: Empty response from Gemini" >&2
            exit 1
        fi
        
        # Check if done (contains completion marker)
        if echo "$content" | grep -qi "done\|complete\|finished"; then
            echo "$content"
            return 0
        fi
    done
    
    echo "Max iterations reached" >&2
    echo "$content"
}

# Export function for sourcing
export -f call_gemini_agent

# If called directly
if [ "$0" = "${BASH_SOURCE[0]}" ]; then
    if [ -z "$1" ]; then
        echo "Usage: $0 '<task description>'"
        exit 1
    fi
    call_gemini_agent "$1"
fi
