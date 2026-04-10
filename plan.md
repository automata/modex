# modex — A Mojo-based AI Coding Harness

## Overview

**modex** is an AI coding agent / harness written in Mojo, inspired by [pi-coding-agent](https://github.com/badlogic/pi-mono/blob/main/packages/coding-agent/). The goal is a minimal, extensible terminal coding agent that gives an LLM tools (read, write, edit, bash) and lets users interact with it conversationally — all implemented in Mojo for performance and as a showcase of the language.

---

## Architecture (Layers)

Pi's architecture breaks into these layers. modex mirrors them:

```
┌─────────────────────────────────────────┐
│  TUI / Interactive Mode                 │  ← Terminal UI, editor, rendering
├─────────────────────────────────────────┤
│  Agent Session                          │  ← Session lifecycle, compaction, events
├─────────────────────────────────────────┤
│  Agent Core                             │  ← Turn loop: prompt → LLM → tool calls → repeat
├─────────────────────────────────────────┤
│  LLM Client (Provider API)              │  ← HTTP + SSE streaming to Anthropic/OpenAI/etc.
├─────────────────────────────────────────┤
│  Tools                                  │  ← read, write, edit, bash
├─────────────────────────────────────────┤
│  Session Storage                        │  ← JSONL tree-structured persistence
└─────────────────────────────────────────┘
```

---

## Milestone 1: Foundation — LLM Client & Streaming

**Goal:** Talk to an LLM API and stream responses back.

### Tasks

- [ ] **HTTP client** — Mojo doesn't have a built-in HTTP client with SSE support. Options:
  - Use Mojo's `Python` interop to call `httpx` or `requests` for bootstrapping
  - Write a minimal HTTP/1.1 client over Mojo's socket API
  - Use `libc` FFI to call `libcurl`
  - **Recommendation:** Start with Python interop (`httpx` with SSE), move to native later
- [ ] **JSON parsing** — Need JSON serialization/deserialization for API payloads
  - Mojo has no stdlib JSON parser yet
  - Options: Python interop (`json` module), or a simple hand-rolled parser
  - **Recommendation:** Python interop initially, native parser as a follow-up
- [ ] **Anthropic Messages API client** — Start with one provider
  - Streaming via SSE (`text/event-stream`)
  - Handle `message_start`, `content_block_delta`, `message_stop` events
  - Support tool use blocks in responses
- [ ] **API key management** — Read from env vars (`ANTHROPIC_API_KEY`)
- [ ] **Model definitions** — Struct for model metadata (id, name, context window, cost, capabilities)

### Deliverable
A CLI that sends a prompt to Claude and streams the response to stdout.

---

## Milestone 2: Tool System

**Goal:** Define tools, send them to the LLM, execute tool calls, return results.

### Tasks

- [ ] **Tool trait/protocol** — Define the tool interface:
  ```
  trait Tool:
      fn name(self) -> String
      fn description(self) -> String
      fn parameters_schema(self) -> JSONSchema
      fn execute(self, params: JSONObject) -> ToolResult
  ```
- [ ] **Tool: `read`** — Read file contents (text + image support)
  - Path resolution (relative to cwd)
  - Line offset/limit for large files
  - Output truncation (50KB / 2000 lines)
- [ ] **Tool: `write`** — Write/overwrite files, create parent dirs
- [ ] **Tool: `edit`** — Find-and-replace exact text in files
- [ ] **Tool: `bash`** — Execute shell commands
  - Subprocess spawning (Mojo's `os` module or `libc` FFI)
  - Stdout/stderr capture
  - Timeout support
  - Output truncation
- [ ] **Tool call loop** — Parse tool_use blocks from LLM response → execute → send tool_result → repeat until LLM stops calling tools
- [ ] **System prompt** — Build the default system prompt with tool descriptions

### Deliverable
A CLI where you can ask the LLM to read files, write code, run commands — the core coding agent loop.

---

## Milestone 3: Session Management

**Goal:** Persist conversations and support resuming.

### Tasks

- [ ] **JSONL session format** — Tree-structured entries with `id` and `parentId`
  - Message entries (user, assistant, toolResult)
  - Metadata entries (model, timestamps)
  - Compatible with pi's format if feasible
- [ ] **Session file I/O** — Append-only JSONL writes, full reads on load
- [ ] **Session directory structure** — `~/.modex/sessions/` organized by cwd hash
- [ ] **Continue/resume** — `-c` to continue most recent, `-r` to browse
- [ ] **Branching** — Navigate to earlier points, branch from there
- [ ] **In-memory sessions** — For ephemeral/testing use

### Deliverable
Sessions auto-save and can be resumed across restarts.

---

## Milestone 4: Terminal UI (TUI)

**Goal:** Interactive terminal interface with editor, chat display, and keyboard navigation.

### Tasks

- [ ] **Terminal raw mode** — Handle raw terminal input (Mojo FFI to termios)
- [ ] **ANSI rendering** — Text styling, colors, cursor movement
  - Or wrap a C TUI library via FFI (e.g., notcurses)
- [ ] **Layout engine** — Simple box model: header, messages area (scrollable), editor, footer
- [ ] **Editor component** — Multi-line text input
  - Basic editing (insert, delete, cursor movement, word operations)
  - Shift+Enter for newlines
  - History (up/down)
- [ ] **Message rendering** — Display user messages, assistant text, tool calls/results
  - Syntax highlighting for code blocks (basic)
  - Collapsible tool output
- [ ] **Keyboard shortcuts** — Ctrl+C (clear/quit), Escape (abort), Ctrl+L (model select)
- [ ] **Streaming display** — Show tokens as they arrive from the LLM

### Deliverable
A full interactive terminal UI for chatting with the agent.

---

## Milestone 5: Multi-Provider Support

**Goal:** Support multiple LLM providers beyond Anthropic.

### Tasks

- [ ] **OpenAI Chat Completions API** — GPT-4o, o1, etc.
- [ ] **OpenAI Responses API** — Newer OpenAI endpoint
- [ ] **Google Gemini API** — Gemini models
- [ ] **Provider abstraction** — Common interface across providers
  - Normalize message formats
  - Normalize tool call/result formats
  - Handle provider-specific quirks (thinking blocks, token counting)
- [ ] **Model registry** — List available models per provider
- [ ] **Model selection UI** — `/model` command, Ctrl+L picker
- [ ] **API key storage** — `~/.modex/auth.json` for persisted keys

### Deliverable
Switch between Claude, GPT-4o, and Gemini models within the same session.

---

## Milestone 6: Context & Customization

**Goal:** Support AGENTS.md, system prompt customization, and settings.

### Tasks

- [ ] **AGENTS.md loading** — Walk up from cwd, concatenate all found files
- [ ] **System prompt override** — `.modex/SYSTEM.md`
- [ ] **Settings** — `~/.modex/settings.json` (global) + `.modex/settings.json` (project)
  - Thinking level, default model, compaction settings
- [ ] **Compaction** — Summarize old messages when approaching context limit
  - Manual (`/compact`)
  - Automatic (on overflow or proactive)
- [ ] **Slash commands** — `/new`, `/resume`, `/model`, `/compact`, `/quit`, etc.

### Deliverable
Project-aware agent that reads instructions from AGENTS.md and manages context intelligently.

---

## Milestone 7: Extensibility

**Goal:** Plugin system for extending modex.

### Tasks

- [ ] **Extension loading** — Load Mojo modules from `~/.modex/extensions/` and `.modex/extensions/`
  - Mojo doesn't have dynamic loading yet — options:
    - Compile extensions as separate binaries, communicate via IPC/stdin-stdout
    - Use Python interop for extensions (write extensions in Python)
    - Compile extensions into the binary at build time (static extension registration)
  - **Recommendation:** Start with Python-based extensions via interop, add Mojo native later
- [ ] **Extension API** — Event hooks, tool registration, command registration
- [ ] **Event system** — `session_start`, `tool_call`, `agent_end`, etc.
- [ ] **Skills** — Markdown-based capability packages (SKILL.md files)
- [ ] **Prompt templates** — Reusable prompts as `.md` files

### Deliverable
Users can add custom tools, commands, and event handlers.

---

## Milestone 8: Advanced Features

**Goal:** Parity with pi's advanced capabilities.

### Tasks

- [ ] **Print mode** — `modex -p "query"` for non-interactive use
- [ ] **JSON mode** — `--mode json` for structured output
- [ ] **File arguments** — `modex @file.ts "Review this"`
- [ ] **Image support** — Paste images, send to vision models
- [ ] **Tree navigation** — `/tree` command for browsing session history
- [ ] **Fork** — `/fork` to create new session from branch point
- [ ] **Export** — Export sessions to HTML
- [ ] **Message queue** — Steering and follow-up messages during streaming

### Deliverable
Feature-complete coding agent.

---

## Key Technical Challenges

### 1. Mojo's Ecosystem Gaps
Mojo is young. Key missing pieces:
- **~~No HTTP client~~** — ✅ Solved: native libc socket FFI works (`libs/http_client/`). Python `requests` interop also works as fallback.
- **No JSON parser** — Need to build or bridge. Start native (it's a good Mojo exercise), fall back to Python `json` if needed.
- **No async/await** — Mojo has no async runtime; need to handle streaming with threads or blocking I/O
- **No dynamic module loading** — Extensions can't be loaded at runtime natively
- **String API in flux** — Nightly changes frequently: `s[i]` requires `byte=` keyword, slicing returns `StringSlice` (needs `String()` wrapping), `@value` removed, `alloc` is a free function, move init uses `deinit take` syntax. Track nightly changes carefully.

**Strategy:** Build native implementations in `libs/` where feasible (HTTP, JSON, TUI). Use Python interop for TLS/HTTPS until native OpenSSL FFI is built.

### 2. Terminal I/O
Mojo has no terminal UI library. Options:
- FFI to `ncurses` or `notcurses`
- Direct ANSI escape codes via stdout + termios for raw mode
- Python interop to `blessed` or `prompt_toolkit`

**Recommendation:** Direct ANSI + termios FFI in `libs/tui/`. Lower-level but avoids heavy dependencies and is a good Mojo exercise.

### 3. Subprocess Management
Tool execution (especially `bash`) needs subprocess spawning with:
- stdout/stderr capture
- Timeout/kill support
- Non-blocking reads for streaming output

Mojo stdlib has `posix_spawnp`, `pipe`, `waitpid`, `kill` in `sys._libc`. Can also use `subprocess.Process` from stdlib.

### 4. SSE Streaming
LLM APIs stream via Server-Sent Events. Need:
- Chunked HTTP response reading (extend `TcpSocket.recv()` to stream incrementally)
- Line-by-line event parsing (`libs/sse/`)
- Token-by-token display updates

### 5. TLS/HTTPS
The native HTTP client only supports plain HTTP. For HTTPS (required by all LLM APIs):
- **Option A:** FFI to OpenSSL/libssl — wrap `SSL_new`, `SSL_connect`, `SSL_read`, `SSL_write`
- **Option B:** Python interop for HTTPS requests (proven to work)
- **Recommendation:** Start with Python interop for LLM API calls, build native TLS later

---

## Project Structure

Each directory under `libs/` is a self-contained Mojo package with its own
`__init__.mojo`. These can be extracted and published as independent open
source libraries — no modex dependencies needed. The `src/` directory holds
the modex application, which imports from `libs/` via `-I libs`.

```
modex/
├── plan.md                          # This file
├── mojoproject.toml                 # Mojo project config, tasks, deps
├── README.md                        # Setup & development guide
├── AGENTS.md                        # Project instructions for AI
│
├── src/
│   └── main.mojo                    # Entry point & CLI
│
├── libs/                            # Extractable Mojo packages
│   │
│   ├── http_client/                 # ✅ HTTP/1.1 client (native libc sockets)
│   │   ├── __init__.mojo            #    Exports: HttpClient, HttpResponse
│   │   ├── client.mojo              #    High-level API: get(), post(), request()
│   │   ├── net.mojo                 #    Socket FFI: TcpSocket, resolve_host()
│   │   └── response.mojo           #    Response parser: status, headers, body
│   │
│   ├── json/                        # JSON parser & serializer
│   │   ├── __init__.mojo            #    Exports: JsonValue, parse, stringify
│   │   ├── parser.mojo              #    JSON tokenizer & parser
│   │   ├── value.mojo               #    JsonValue type (object, array, string, etc.)
│   │   └── serializer.mojo          #    JSON serialization
│   │
│   ├── sse/                         # Server-Sent Events stream parser
│   │   ├── __init__.mojo            #    Exports: SseParser, SseEvent
│   │   └── parser.mojo              #    Line-by-line SSE event parsing
│   │
│   ├── llm/                         # LLM provider clients
│   │   ├── __init__.mojo            #    Exports: provider interfaces, model types
│   │   ├── types.mojo               #    Model, Message, ToolCall, ToolResult
│   │   ├── anthropic.mojo           #    Anthropic Messages API
│   │   ├── openai.mojo              #    OpenAI Chat/Responses API
│   │   └── google.mojo              #    Google Gemini API
│   │
│   ├── tui/                         # Terminal UI framework
│   │   ├── __init__.mojo            #    Exports: Terminal, Editor, Layout
│   │   ├── terminal.mojo            #    Raw mode, ANSI codes (termios FFI)
│   │   ├── editor.mojo              #    Multi-line text editor component
│   │   ├── layout.mojo              #    Box model layout engine
│   │   └── renderer.mojo            #    Text styling & rendering
│   │
│   └── tools/                       # Coding agent tool implementations
│       ├── __init__.mojo            #    Exports: Tool trait, built-in tools
│       ├── tool.mojo                #    Tool trait & registry
│       ├── read.mojo                #    Read file tool
│       ├── write.mojo               #    Write file tool
│       ├── edit.mojo                #    Find-and-replace edit tool
│       └── bash.mojo                #    Shell command execution tool
│
├── experiments/                     # Standalone experiments & spikes
│   ├── http_client.mojo             #    Python interop HTTP client
│   └── http_client_native.mojo      #    Native libc socket HTTP client
│
└── tests/                           # Tests (pixi run test)
    ├── test_http_client.mojo
    ├── test_json.mojo
    ├── test_tools.mojo
    └── test_agent.mojo
```

### What lives in `src/` vs `libs/`

- **`libs/`** — Generic, reusable packages. No modex-specific logic. Each
  could be its own repo/package. Examples: `http_client`, `json`, `tui`.
- **`src/`** — The modex application: agent loop, session management,
  compaction, CLI, config, AGENTS.md loading. Imports from `libs/`.

### Extracting a library

To publish a lib independently:

1. Copy the `libs/<name>/` directory to a new repo
2. Add a `mojoproject.toml` with any dependencies
3. Users add it to their import path with `-I` or `MOJO_IMPORT_PATH`

```mojo
// Works in any Mojo project with the package on the import path:
from http_client import HttpClient
from json import parse, stringify
```

---

## Dependencies & Tooling

- **Mojo** (nightly) — Installed via pixi from `max-nightly` channel
- **pixi** — Package manager for Mojo and Python dependencies
- **Python `requests`** — For Python interop HTTP (pixi dependency, used in experiments)
- **libc** — For native sockets, termios, subprocess (via Mojo FFI, no extra install)

---

## MVP Definition (Milestones 1-2)

The minimum viable product is a CLI that:
1. Takes a user prompt
2. Sends it to Claude with tool definitions
3. Streams the response
4. Executes tool calls (read, write, edit, bash)
5. Loops until the LLM stops calling tools
6. Prints the final response

This is achievable without a TUI — just stdin/stdout. The TUI and session management come after.

---

## Resolved Questions

1. **~~Mojo version pinning~~** — Tracking nightly (`max = "*"` from `max-nightly` channel). Pin in `mojoproject.toml` if stability needed.
2. **~~Python interop overhead~~** — Negligible for network I/O. Native libc FFI also works (proven in experiments). Use native for the core HTTP client, Python interop as fallback for TLS/HTTPS until native OpenSSL FFI is built.
3. **~~Project structure~~** — `libs/` for extractable packages, `src/` for modex app. Each lib is self-contained with `__init__.mojo`.

## Open Questions

1. **Extension model** — Should extensions be Python scripts, compiled Mojo packages, or IPC-based plugins?
2. **Compatibility with pi** — Should session files be compatible? Same AGENTS.md format?
3. **TLS/HTTPS** — Link OpenSSL via FFI, or use Python interop for HTTPS?
4. **Licensing** — MIT to match pi?
