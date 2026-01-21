#!/bin/bash
# Backend Agent: Handles backend development tasks.

set -e

if [ -z "$1" ]; then
    echo "{\"error\":\"No task description provided to backend agent.\"}"
    exit 1
fi

TASK_DESC="$1"
CONTEXT_DIR=$(pwd)

# This prompt is highly specific to the backend agent's role.
# It tells Gemini exactly what persona to adopt and what to do.
GEMINI_PROMPT="
Actúa como un INGENIERO BACKEND senior.

Contexto del proyecto (directorio actual): $CONTEXT_DIR
Archivos de memoria (disponibles para leer en ./.gsd/):
- context.md
- decisions.md
- todos.md

Tu tarea específica es:
\"$TASK_DESC\"

Basado en esta tarea, tu entregable es un objeto JSON con las siguientes claves:
- \"design_notes\": Un string con tus pensamientos, el enfoque y el diseño para la tarea.
- \"files_to_modify\": Un array de strings con las rutas de los archivos que planeas modificar.
- \"code_changes\": Un array de objetos, donde cada objeto tiene \"file_path\" y \"new_content\" para el código que vas a generar o cambiar.
- \"summary\": Un resumen conciso del trabajo que realizaste.
"

# Call the gemini CLI with the constructed prompt.
# The output of this script will be captured by the planner.
gemini -p "$GEMINI_PROMPT" --output-format json --yolo

