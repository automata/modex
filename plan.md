# modex — A Mojo-based AI Coding Harness

## Overview

**modex** is an AI coding agent / harness written in Mojo,
inspired by [pi-coding-agent](https://github.com/badlogic/pi-mono/blob/main/packages/coding-agent/).
The goal is a minimal, extensible terminal coding agent that gives an LLM tools
(read, write, edit, bash) and lets users interact with it conversationally,
all implemented in Mojo for performance and as a showcase of the language.

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
│  LLM Client (Provider API)              │  ← HTTP + SSE streaming to OpenRouter/OpenAI/etc.
├─────────────────────────────────────────┤
│  Tools                                  │  ← read, write, edit, bash
├─────────────────────────────────────────┤
│  Session Storage                        │  ← JSONL tree-structured persistence
└─────────────────────────────────────────┘
```

---

## Milestone 1: Foundation — LLM Client & Streaming

**Goal:** Talk to an LLM API and stream responses back.

### Status

**Substantially implemented.** The transport/provider foundation exists and works.

### Tasks

- [x] **HTTP client** — Implemented as a native HTTP/1.1 client over libc sockets in `libs/http_client/`
  - [x] Plain HTTP via libc socket FFI
  - [x] HTTPS via OpenSSL `libssl`/`libcrypto` FFI
  - [x] Incremental header reading
  - [x] Custom headers and POST support
- [ ] **JSON parsing** — Not yet native
  - [x] Python interop (`json`) works for payload serialization/deserialization
  - [ ] Native Mojo JSON parser/serializer still needed (`libs/json/`)
- [x] **OpenRouter API client** — Implemented in `libs/llm/openrouter.mojo`
  - [x] OpenAI-compatible Chat Completions API via OpenRouter
  - [x] Streaming responses over SSE
  - [x] Text delta parsing
  - [x] Tool-call delta parsing
  - [x] Live callback streaming
- [x] **API key management** — Reads from env vars (`OPENROUTER_API_KEY`)
- [ ] **Model definitions** — Minimal model handling exists (pass model ID string), but no full model registry/metadata structs yet
- [x] **SSE parser** — Implemented in `libs/sse/`
- [x] **Chunked transfer decoding** — Implemented in `libs/http_client/`

### Deliverable

A CLI/experiment can send a prompt through OpenRouter and stream the response to stdout. This is working today (`experiments/openrouter_stream.mojo`, `experiments/openrouter_stream_live.mojo`).

---

## Milestone 2: Tool System

**Goal:** Define tools, send them to the LLM, execute tool calls, return results.

### Status

**Partially implemented.** Provider-side tool calling is now supported; execution-side tools are not yet implemented.

### Tasks

- [ ] **Tool trait/protocol** — Define the tool interface:

  ```
  trait Tool:
      fn name(self) -> String
      fn description(self) -> String
      fn parameters_schema(self) -> JSONSchema
      fn execute(self, params: JSONObject) -> ToolResult
  ```

- [x] **Provider-side tool definitions** — `OpenRouterToolSpec` implemented and sent in provider payloads
- [x] **Provider-side tool-call parsing** — Streamed tool call deltas are parsed from OpenRouter SSE frames
- [x] **Tool-call assembly** — `assemble_tool_calls(...)` reconstructs full tool calls from streamed partial deltas
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
- [ ] **Tool execution loop** — Parse tool calls → execute tools → send tool results back to model → repeat until final assistant response
- [ ] **System prompt** — Build the default system prompt with tool descriptions

### Deliverable

A CLI where you can ask the LLM to read files, write code, run commands — the full coding-agent loop. Current state: tool-call transport/parsing works, but tool execution is not yet connected.

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

**Goal:** Support multiple LLM providers beyond OpenRouter.

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

Switch between OpenRouter-routed models, direct GPT-4o, and Gemini models within the same session.

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

LLM APIs stream via Server-Sent Events.

- [x] Chunked HTTP response reading (incremental)
- [x] Line-by-line event parsing (`libs/sse/`)
- [x] Buffered SSE collection (`HttpClient.get_sse()` / `post_sse()`)
- [x] Live callback streaming in `OpenRouterClient`
- [ ] Token-by-token display in a TUI

### 5. TLS/HTTPS

- [x] OpenSSL `libssl` / `libcrypto` FFI implemented
- [x] HTTPS requests working against OpenRouter and other hosts
- [ ] Proper IPv6 + multi-address fallback (currently forced to IPv4 because socket layer only supports `sockaddr_in`)

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
│   ├── http_client/                 # ✅ implemented
│   │   ├── __init__.mojo            #    Exports: HttpClient, HttpHeader, HttpResponse
│   │   ├── client.mojo              #    HTTP requests, SSE fetch, chunked stream decoder
│   │   ├── net.mojo                 #    Socket FFI: TcpSocket, resolve_host()
│   │   ├── response.mojo            #    Response parser: status, headers, body
│   │   └── tls.mojo                 #    OpenSSL-based TLS socket
│   │
│   ├── sse/                         # ✅ implemented
│   │   ├── __init__.mojo            #    Exports: SseParser, SseEvent
│   │   └── parser.mojo              #    Incremental SSE parser
│   │
│   ├── llm/                         # ✅ partially implemented
│   │   ├── __init__.mojo            #    Exports: OpenRouter client/types/helpers
│   │   └── openrouter.mojo          #    OpenRouter streaming client + tool-call parsing
│   │
│   ├── json/                        # planned
│   ├── tui/                         # planned
│   └── tools/                       # planned
│
├── experiments/                     # Standalone experiments & spikes
│   ├── http_client.mojo             #    Python interop HTTP client
│   ├── http_client_native.mojo      #    Native libc socket HTTP client
│   ├── openrouter_stream.mojo       #    Buffered OpenRouter streaming
│   ├── openrouter_stream_live.mojo  #    Live callback OpenRouter streaming
│   └── sse_parser.mojo              #    Standalone SSE parser demo
│
└── tests/                           # Tests (pixi run test)
    # tests not implemented yet
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
2. Sends it through OpenRouter with tool definitions
3. Streams the response
4. Executes tool calls (read, write, edit, bash)
5. Loops until the LLM stops calling tools
6. Prints the final response

This is achievable without a TUI — just stdin/stdout. The TUI and session management come after.

---

## Resolved Questions

1. **~~Mojo version pinning~~** — Tracking nightly (`max = "*"` from `max-nightly` channel). Pin in `mojoproject.toml` if stability needed.
2. **~~Python interop overhead~~** — Negligible for network I/O. Native libc FFI also works (proven in experiments).
3. **~~Project structure~~** — `libs/` for extractable packages, `src/` for modex app. Each lib is self-contained with `__init__.mojo`.
4. **~~TLS/HTTPS~~** — Implemented via OpenSSL FFI in `libs/http_client/tls.mojo`.
5. **~~Initial provider~~** — OpenRouter implemented first, including live streaming and tool-call parsing.

## Open Questions

1. **Tool execution loop design** — Should tool execution be provider-agnostic in a shared agent layer, or start with an OpenRouter-specific loop and generalize later?
2. **Extension model** — Should extensions be Python scripts, compiled Mojo packages, or IPC-based plugins?
3. **Compatibility with pi** — Should session files be compatible? Same AGENTS.md format?
4. **Licensing** — MIT to match pi?
5. **IPv6 support** — Add full `sockaddr_in6` + multi-address fallback now, or defer until after the agent loop?
