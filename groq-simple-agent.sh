#!/bin/bash
# Simple Action-based Agent Executor
# Agent returns JSON actions, we execute them

set -e

# Load environment variables
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
if [ -f "$SCRIPT_DIR/.env" ]; then
    export $(grep -v '^#' "$SCRIPT_DIR/.env" | xargs)
fi

# Defaults to avoid rate limits
: "${GROQ_RETRY_LIMIT:=3}"
: "${GROQ_BACKOFF_SECONDS:=2}"
: "${GROQ_BETWEEN_ITER_SECONDS:=1}"
: "${GROQ_BETWEEN_ACTIONS_SECONDS:=1}"

# Low-temp, low-max tokens to save quota
: "${GROQ_TEMPERATURE:=0.4}"
: "${GROQ_MAX_TOKENS:=2000}"

# Internal helper: Groq chat with retries/backoff
groq_chat_request() {
    local payload="$1"
    local attempt=1
    local backoff=$GROQ_BACKOFF_SECONDS

    while true; do
        local response=$(curl -s -X POST "$GROQ_API_URL" \
            -H "Authorization: Bearer $GROQ_API_KEY" \
            -H "Content-Type: application/json" \
            -d "$payload")

        if echo "$response" | jq -e '.error' > /dev/null; then
            local msg=$(echo "$response" | jq -r '.error.message // ""')
            if echo "$msg" | grep -qi "rate limit" && [ $attempt -lt $GROQ_RETRY_LIMIT ]; then
                echo "[Groq] Rate limited, retrying in ${backoff}s (attempt $attempt)" >&2
                sleep $backoff
                attempt=$((attempt + 1))
                backoff=$((backoff * 2))
                continue
            fi
            echo "Groq API Error: $msg" >&2
            return 1
        fi

        echo "$response"
        return 0
    done
}

# Execute an action
execute_action() {
    local action_type="$1"
    local params="$2"
    
    case "$action_type" in
        "bash")
            local cmd=$(echo "$params" | jq -r '.command')
            echo "[Executing: $cmd]" >&2
            eval "$cmd" 2>&1
            ;;
        "write_file")
            local path=$(echo "$params" | jq -r '.path')
            local content=$(echo "$params" | jq -r '.content')
            echo "[Writing: $path]" >&2
            mkdir -p "$(dirname "$path")"
            echo "$content" > "$path"
            echo "✓ File written: $path"
            ;;
        "read_file")
            local path=$(echo "$params" | jq -r '.path')
            echo "[Reading: $path]" >&2
            cat "$path" 2>&1
            ;;
        *)
            echo "Unknown action: $action_type" >&2
            ;;
    esac
}

# Call Groq and execute actions iteratively
call_groq_agent() {
    local task_prompt="$1"
    local max_iterations=${2:-15}
    
    local full_prompt="$task_prompt

IMPORTANT: You must complete the task by taking actions. After each response, you can either:
1. Execute actions by providing a JSON object with \"actions\" array
2. Finish by providing a JSON object with \"done\": true and \"summary\"

Available actions:
- bash: {\"type\": \"bash\", \"params\": {\"command\": \"<shell command>\"}}
- write_file: {\"type\": \"write_file\", \"params\": {\"path\": \"<file path>\", \"content\": \"<file content>\"}}
- read_file: {\"type\": \"read_file\", \"params\": {\"path\": \"<file path>\"}}

Response format for actions:
{\"actions\": [{\"type\": \"bash\", \"params\": {\"command\": \"ls -la\"}}], \"reasoning\": \"why you're doing this\"}

Response format when done:
{\"done\": true, \"summary\": \"Brief description of what you accomplished\"}

Start working on the task now."
    
    local conversation_history="[{\"role\": \"user\", \"content\": $(echo "$full_prompt" | jq -Rs .)}]"
    
    for iteration in $(seq 1 $max_iterations); do
        echo "[Iteration $iteration]" >&2
        
        # Call Groq
        local response=$(groq_chat_request "{\"model\":\"$GROQ_MODEL\",\"messages\":$conversation_history,\"temperature\":$GROQ_TEMPERATURE,\"max_tokens\":$GROQ_MAX_TOKENS}")
        [ $? -ne 0 ] && exit 1
        
        local content=$(echo "$response" | jq -r '.choices[0].message.content')
        
        # Add assistant response to history
        conversation_history=$(echo "$conversation_history" | jq --arg content "$content" '. += [{role: "assistant", content: $content}]')
        
        # Try to parse JSON from the response (handle markdown code blocks)
        local json_content=$(echo "$content" | sed -n '/```json/,/```/p' | sed '1d;$d')
        if [ -z "$json_content" ]; then
            json_content="$content"
        fi
        
        # Check if done
        if echo "$json_content" | jq -e '.done == true' > /dev/null 2>&1; then
            local summary=$(echo "$json_content" | jq -r '.summary')
            echo "$summary"
            return 0
        fi
        
        # Execute actions
        if echo "$json_content" | jq -e '.actions' > /dev/null 2>&1; then
            local num_actions=$(echo "$json_content" | jq '.actions | length')
            local action_results=""
            
            for i in $(seq 0 $(($num_actions - 1))); do
                local action=$(echo "$json_content" | jq -c ".actions[$i]")
                local action_type=$(echo "$action" | jq -r '.type')
                local params=$(echo "$action" | jq -c '.params')
                
                local result=$(execute_action "$action_type" "$params")
                action_results="$action_results\n- $action_type: $result"
            done
            
            # Add results to conversation
            local feedback="Actions executed successfully. Results:$action_results\n\nContinue or finish if done."
            conversation_history=$(echo "$conversation_history" | jq --arg feedback "$feedback" '. += [{role: "user", content: $feedback}]')

            # Small delay between iterations to ease rate limits
            sleep $GROQ_BETWEEN_ACTIONS_SECONDS
        else
            # No valid JSON, ask for proper format
            conversation_history=$(echo "$conversation_history" | jq '. += [{role: "user", content: "Please provide a valid JSON response with either actions to execute or mark as done."}]')
        fi

        sleep $GROQ_BETWEEN_ITER_SECONDS
    done
    
    echo "Task completed after $max_iterations iterations (summary may be incomplete)"
}

# Export function for sourcing
export -f call_groq_agent execute_action

# If called directly
if [ "$0" = "${BASH_SOURCE[0]}" ]; then
    if [ -z "$1" ]; then
        echo "Usage: $0 '<task description>'"
        exit 1
    fi
    call_groq_agent "$1"
fi
