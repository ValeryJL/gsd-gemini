#!/bin/bash
# Planner Agent: The main orchestrator script.

set -e # Exit immediately if a command exits with a non-zero status.

# --- Configuration & Setup ---
# Get the absolute path of the directory where this script is located.
# This allows us to reliably call other agent scripts in the same directory.
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)

# Add all agent scripts to this list
declare -A AGENT_SCRIPTS=(
    ["planner"]="$SCRIPT_DIR/planner.sh"
    ["architect"]="$SCRIPT_DIR/architect.sh"
    ["backend"]="$SCRIPT_DIR/backend.sh"
    ["frontend"]="$SCRIPT_DIR/frontend.sh"
    ["db"]="$SCRIPT_DIR/db.sh"
    ["reviewer"]="$SCRIPT_DIR/reviewer.sh"
)

# Function to ensure the .gsd directory and essential files exist.
ensure_gsd_dir() {
    if [ ! -d ".gsd" ]; then
        echo "Initializing .gsd directory in $(pwd)..."
        mkdir -p .gsd/tasks
        touch .gsd/context.md
        touch .gsd/decisions.md
        touch .gsd/todos.md
    fi
}

# --- Argument Parsing ---
AUTO_MODE=false
USER_PROMPT=""

while [[ "$#" -gt 0 ]]; do
    case $1 in
        -a|--auto) AUTO_MODE=true ;;
        *) USER_PROMPT="$1" ;;
    esac
    shift
done

if [ -z "$USER_PROMPT" ]; then
    echo "Usage: planner.sh \"<your-high-level-task>\" [-a|--auto]"
    echo "Note: This script requires 'jq' to be installed for JSON parsing."
    exit 1
fi

# --- Main Execution ---
ensure_gsd_dir
CURRENT_PROMPT="$USER_PROMPT"
ITERATION=1

while true; do
    echo "--- Iteration $ITERATION ---"

    # 1. PLANNING STEP
    # Call Gemini to break down the current prompt into a structured plan (JSON).
    echo "Planning... Asking for a task breakdown."
    PLANNER_PROMPT="
You are a master software engineering project planner. Your job is to take a high-level goal and break it down into a series of small, atomic, sequential tasks. Each task must be assigned to a specific agent.

You MUST return your response as a single, valid JSON object.
The JSON object should contain one key: \"tasks\".
The value of \"tasks\" should be an array of task objects.
Each task object must have two keys: \"agent\" and \"task_description\".

The available agents are: ${!AGENT_SCRIPTS[*]}

Goal: \"$CURRENT_PROMPT\"

Provide the JSON response now.
"
    # Note: The user requested --yolo. If 'gemini' doesn't support it, it may need to be removed.
    # We are simulating the call here. Replace with the actual gemini call.
    # SIMULATED_JSON_RESPONSE='{"tasks":[{"agent":"architect","task_description":"Design the overall structure."},{"agent":"backend","task_description":"Implement the main API endpoint."}]}'
    # TASK_LIST_JSON=$(echo "$SIMULATED_JSON_RESPONSE")
    
    TASK_LIST_JSON=$(gemini -p "$PLANNER_PROMPT" --output-format json --yolo)

    echo "Plan received:"
    echo "$TASK_LIST_JSON" | jq .

    # 2. EXECUTION STEP
    # Iterate over the tasks and execute the corresponding agent.
    ALL_AGENT_OUTPUTS=""
    TASK_COUNT=$(echo "$TASK_LIST_JSON" | jq '.tasks | length')

    for i in $(seq 0 $(($TASK_COUNT - 1))); do
        TASK_OBJ=$(echo "$TASK_LIST_JSON" | jq ".tasks[$i]")
        AGENT_NAME=$(echo "$TASK_OBJ" | jq -r '.agent')
        TASK_DESC=$(echo "$TASK_OBJ" | jq -r '.task_description')

        echo "Executing task for agent: $AGENT_NAME"
        echo "Task: $TASK_DESC"

        AGENT_SCRIPT_PATH=${AGENT_SCRIPTS[$AGENT_NAME]}
        
        if [ -z "$AGENT_SCRIPT_PATH" ] || [ ! -f "$AGENT_SCRIPT_PATH" ]; then
            echo "Error: Agent '$AGENT_NAME' not found or script not executable."
            exit 1
        fi

        # Execute the agent script and capture its output
        # The agent scripts are expected to be simple and just take the task description as an argument
        AGENT_OUTPUT=$("$AGENT_SCRIPT_PATH" "$TASK_DESC")
        ALL_AGENT_OUTPUTS+="\n\n--- Output from $AGENT_NAME ---\n$AGENT_OUTPUT"
    done

    # 3. SUMMARIZATION STEP
    echo "Summarizing iteration results..."
    SUMMARY_PROMPT="
You are a senior tech lead. You have received a series of outputs from different agents working on a task. Your job is to summarize their work and determine if the original goal has been met.

Original Goal: \"$USER_PROMPT\"
Summary of previous work: \"$CURRENT_PROMPT\"
Outputs from this iteration:
$ALL_AGENT_OUTPUTS

Your task:
1. Summarize the work done in this iteration.
2. Determine the project status.
3. Provide a new high-level prompt for the next iteration if the goal is not met.

You MUST return a single, valid JSON object with three keys:
- \"summary\": A concise summary of the work completed.
- \"status\": Either \"complete\" or \"incomplete\".
- \"next_prompt\": A clear, high-level prompt for the planner in the next iteration. If the status is \"complete\", this can be an empty string.
"
    # SUMMARY_JSON=$(echo '{"summary":"The agents designed and implemented the API.","status":"incomplete","next_prompt":"Now, create the frontend for the API."}')
    SUMMARY_JSON=$(gemini -p "$SUMMARY_PROMPT" --output-format json --yolo)
    
    STATUS=$(echo "$SUMMARY_JSON" | jq -r '.status')
    SUMMARY=$(echo "$SUMMARY_JSON" | jq -r '.summary')
    NEXT_PROMPT=$(echo "$SUMMARY_JSON" | jq -r '.next_prompt')

    echo "Iteration Summary: $SUMMARY"
    echo "Status: $STATUS"

    # 4. LOOP CONTROL
    if [ "$STATUS" == "complete" ] || [ "$AUTO_MODE" == false ]; then
        echo "Workflow finished."
        break
    fi

    echo "Goal not yet complete. Preparing for next iteration."
    CURRENT_PROMPT="$NEXT_PROMPT"
    ITERATION=$(($ITERATION + 1))
    # Small delay to prevent runaway loops
    sleep 2
done
