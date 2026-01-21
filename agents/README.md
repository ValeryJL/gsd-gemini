# GSD-Gemini Agent Backends

This directory contains different LLM backend implementations for the GSD-Gemini agent system.

## Supported Backends

### Groq (Active)
- **Status**: ✅ Fully working
- **Location**: `groq/groq-simple-agent.sh`
- **Features**: 
  - Free tier with generous limits (12,000 TPM, 100k TPD)
  - Fast inference
  - Retry/backoff on rate limits
  - Low tokens configuration

**Setup**:
```bash
export AGENT_BACKEND=groq
# Requires: GROQ_API_KEY in .env
```

### Gemini CLI (Planned)
- **Status**: 🔶 Planned
- **Location**: `gemini/gemini-agent.sh`
- **Note**: Requires Gemini CLI installed locally

**Setup**:
```bash
export AGENT_BACKEND=gemini
```

### GitHub Models (Planned)
- **Status**: 🔶 Planned
- **Location**: `github/github-agent.sh`
- **Features**: 
  - Free tier integrated with GitHub
  - Multiple models available
  - Good for automation within GitHub workflows

**Setup**:
```bash
export AGENT_BACKEND=github
# Requires: GITHUB_TOKEN in .env
```

## Usage

Set the backend via environment variable before running gsdgc:

```bash
export AGENT_BACKEND=groq
./gsdgc "your task here"
```

Or add to `.env`:
```
AGENT_BACKEND=groq
```

## Adding a New Backend

1. Create a new directory: `agents/my-backend/`
2. Implement `my-backend-agent.sh` following the interface:
   - Must provide a function that accepts task prompt and max iterations
   - Must handle tool execution (bash, write_file, read_file)
   - Must return JSON with summary on completion
3. Update `agent-dispatcher.sh` to route to your backend
4. Add documentation above

## Environment Variables

Common variables (check `.env.example`):
- `AGENT_BACKEND`: Which backend to use (default: `groq`)
- `GROQ_API_KEY`: For Groq backend
- `GITHUB_TOKEN`: For GitHub backend
- `DEBUG_MODE`: Enable verbose logging
