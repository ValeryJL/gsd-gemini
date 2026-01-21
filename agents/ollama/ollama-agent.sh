#!/bin/bash
# Ollama Agent Executor with Action Support
# Integrates with local Ollama for agent execution

set -e

# Load environment variables
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
if [ -f "$SCRIPT_DIR/.env" ]; then
    export $(grep -v '^#' "$SCRIPT_DIR/.env" | xargs)
fi

# Defaults for Ollama
: "${OLLAMA_API_URL:=http://localhost:11434/api/chat}"
: "${OLLAMA_MODEL:=llama3.2}"
: "${OLLAMA_TEMPERATURE:=0.4}"
: "${OLLAMA_MAX_TOKENS:=2000}"
: "${OLLAMA_RETRY_LIMIT:=3}"
: "${OLLAMA_BETWEEN_ITERATIONS_SECONDS:=0.5}"
: "${OLLAMA_BETWEEN_ACTIONS_SECONDS:=0.2}"

# Helper: Ollama API call with retry
ollama_chat_request() {
    local payload="$1"
    local attempt=1
    local backoff=2

    while true; do
        local response=$(curl -s -X POST "$OLLAMA_API_URL" \
            -H "Content-Type: application/json" \
            -d "$payload")

        # Check if Ollama is running
        if [ -z "$response" ]; then
            if [ $attempt -lt $OLLAMA_RETRY_LIMIT ]; then
                echo "[Ollama] No response, retrying in ${backoff}s (attempt $attempt)" >&2
                echo "[Ollama] Make sure Ollama is running: ollama serve" >&2
                sleep $backoff
                attempt=$((attempt + 1))
                backoff=$((backoff * 2))
                continue
            fi
            echo "Ollama Error: No response. Is Ollama running? (ollama serve)" >&2
            return 1
        fi

        # Check for error in response
        if echo "$response" | jq -e '.error' > /dev/null 2>&1; then
            local msg=$(echo "$response" | jq -r '.error // ""')
            echo "Ollama API Error: $msg" >&2
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

# Execute task using Ollama with action support
call_ollama_agent() {
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
    
    local conversation_history="[]"
    
    for iteration in $(seq 1 $max_iterations); do
        echo "[Iteration $iteration]" >&2
        
        # Add user message to history
        conversation_history=$(echo "$conversation_history" | jq --arg content "$full_prompt" '. += [{role: "user", content: $content}]')
        
        # Call Ollama (stream=false for complete response)
        local payload="{\"model\":\"$OLLAMA_MODEL\",\"messages\":$conversation_history,\"stream\":false,\"options\":{\"temperature\":$OLLAMA_TEMPERATURE,\"num_predict\":$OLLAMA_MAX_TOKENS}}"
        local response=$(ollama_chat_request "$payload") || exit 1
        
        local content=$(echo "$response" | jq -r '.message.content // empty')
        
        if [ -z "$content" ]; then
            echo "Error: Empty response from Ollama" >&2
            exit 1
        fi
        
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
                
                sleep $OLLAMA_BETWEEN_ACTIONS_SECONDS
            done
            
            # Update prompt for next iteration with results
            full_prompt="Actions executed successfully. Results:$action_results\n\nContinue or finish if done."
        else
            # No valid JSON, ask for proper format
            full_prompt="Please provide a valid JSON response with either actions to execute or mark as done."
        fi
        
        sleep $OLLAMA_BETWEEN_ITERATIONS_SECONDS
    done
    
    echo "Task completed after $max_iterations iterations (summary may be incomplete)"
}

# Export function for sourcing
export -f call_ollama_agent ollama_chat_request execute_action

# If called directly
if [ "$0" = "${BASH_SOURCE[0]}" ]; then
    if [ -z "$1" ]; then
        echo "Usage: $0 '<task description>'"
        echo ""
        echo "Make sure Ollama is running:"
        echo "  ollama serve"
        echo ""
        echo "And the model is pulled:"
        echo "  ollama pull $OLLAMA_MODEL"
        exit 1
    fi
    call_ollama_agent "$1"
fi
