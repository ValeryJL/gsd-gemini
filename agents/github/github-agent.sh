#!/bin/bash
# GitHub Models Agent Executor
# Integrates with GitHub Models for agent execution

set -e

# Load environment variables
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
if [ -f "$SCRIPT_DIR/.env" ]; then
    export $(grep -v '^#' "$SCRIPT_DIR/.env" | xargs)
fi

# Defaults for GitHub Models
: "${GITHUB_MODELS_API_URL:=https://models.inference.ai.azure.com/chat/completions}"
: "${GITHUB_MODEL:=gpt-4o}"
: "${GITHUB_TEMPERATURE:=0.4}"
: "${GITHUB_MAX_TOKENS:=2000}"

# Check for required token
if [ -z "$GITHUB_TOKEN" ]; then
    echo "Error: GITHUB_TOKEN not set. GitHub Models backend requires authentication." >&2
    exit 1
fi

# Helper: GitHub API call with retry/backoff
github_chat_request() {
    local payload="$1"
    local attempt=1
    local backoff=2

    while true; do
        local response=$(curl -s -X POST "$GITHUB_MODELS_API_URL" \
            -H "Authorization: Bearer $GITHUB_TOKEN" \
            -H "Content-Type: application/json" \
            -d "$payload")

        if echo "$response" | jq -e '.error' > /dev/null 2>&1; then
            local msg=$(echo "$response" | jq -r '.error.message // ""')
            if echo "$msg" | grep -qi "rate limit" && [ $attempt -lt 3 ]; then
                echo "[GitHub] Rate limited, retrying in ${backoff}s (attempt $attempt)" >&2
                sleep $backoff
                attempt=$((attempt + 1))
                backoff=$((backoff * 2))
                continue
            fi
            echo "GitHub Models API Error: $msg" >&2
            return 1
        fi

        echo "$response"
        return 0
    done
}

# Execute task using GitHub Models
call_github_agent() {
    local task_prompt="$1"
    local max_iterations=${2:-15}
    
    local messages="[{\"role\": \"user\", \"content\": $(echo "$task_prompt" | jq -Rs .)}]"
    
    for iteration in $(seq 1 $max_iterations); do
        echo "[Iteration $iteration]" >&2
        
        # Call GitHub Models
        local payload="{\"model\":\"$GITHUB_MODEL\",\"messages\":$messages,\"temperature\":$GITHUB_TEMPERATURE,\"max_tokens\":$GITHUB_MAX_TOKENS}"
        local response=$(github_chat_request "$payload") || exit 1
        
        # Extract content
        local content=$(echo "$response" | jq -r '.choices[0].message.content // empty')
        
        if [ -z "$content" ]; then
            echo "Error: Empty response from GitHub Models" >&2
            exit 1
        fi
        
        # Add to message history
        messages=$(echo "$messages" | jq --arg content "$content" '. += [{role: "assistant", content: $content}]')
        
        # Check if done
        if echo "$content" | grep -qi "done\|complete\|finished\|summary"; then
            echo "$content"
            return 0
        fi
    done
    
    echo "Max iterations reached" >&2
    echo "$content"
}

# Export function for sourcing
export -f call_github_agent github_chat_request

# If called directly
if [ "$0" = "${BASH_SOURCE[0]}" ]; then
    if [ -z "$1" ]; then
        echo "Usage: $0 '<task description>'"
        exit 1
    fi
    call_github_agent "$1"
fi
