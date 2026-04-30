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
- [x] **JSON parsing** — Native Mojo JSON package implemented in `libs/json/`
  - [x] Native parser for objects, arrays, strings, numbers, bool, null
  - [x] Native serializer/builders for provider payload generation
  - [x] OpenRouter client and built-in tool dispatcher no longer rely on Python `json`
  - [ ] Unicode handling is still minimal (`\uXXXX` outside ASCII is not fully supported yet)
- [x] **OpenRouter API client** — Implemented in `libs/llm/openrouter.mojo`
  - [x] OpenAI-compatible Chat Completions API via OpenRouter
  - [x] Streaming responses over SSE
  - [x] Text delta parsing
  - [x] Tool-call delta parsing
  - [x] Callback streaming
- [x] **API key management** — Reads from env vars (`OPENROUTER_API_KEY`)
- [ ] **Model definitions** — Minimal model handling exists (pass model ID string), but no full model registry/metadata structs yet
- [x] **SSE parser** — Implemented in `libs/sse/`
- [x] **Chunked transfer decoding** — Implemented in `libs/http_client/`
  - [x] Shared chunked decoding extracted to `libs/http_client/chunked.mojo`
  - [x] Shared chunked decoding used across the streaming implementation
  - [x] Decoder made tolerant of both `\r\n` and bare `\n` in chunk framing

### Deliverable

A CLI/experiment can send a prompt through OpenRouter and stream the response to stdout. This is working today (`experiments/openrouter_stream.mojo`, `experiments/openrouter_stream_callback.mojo`).

---

## Milestone 2: Tool System

**Goal:** Define tools, send them to the LLM, execute tool calls, return results.

### Status

**Substantially implemented.** Built-in tools, provider-side tool calling, and a generic multi-turn built-in tool loop are working. Tool safety/sandboxing and a more general pluggable tool protocol still remain.

### Tasks

- [ ] **Tool trait/protocol** — Define the general reusable tool interface:

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
- [x] **Tool: `read`** — Implemented in `libs/tools/read.mojo`
  - [x] Path resolution relative to cwd
  - [x] Line offset/limit support
  - [x] Output truncation behavior
  - [ ] Image support not implemented yet
- [x] **Tool: `write`** — Implemented in `libs/tools/write.mojo`
- [x] **Tool: `edit`** — Implemented in `libs/tools/edit.mojo`
- [x] **Tool: `bash`** — Implemented in `libs/tools/bash.mojo`
  - [x] Subprocess execution
  - [x] Stdout/stderr capture
  - [x] Timeout support
  - [x] Output truncation
- [x] **App-level tool execution loop** — current REPL in `src/main.mojo` orchestrates tool execution using `OpenRouter.create(...)`
- [ ] **System prompt** — Default reusable system prompt layer still needed
- [ ] **Tool safety / sandboxing** — Path restrictions, permission model, safer write/edit semantics still needed

### Deliverable

A CLI/experiment where you can ask the LLM to read files, write code, run commands, and complete a multi-turn tool loop. Current state: this works, with provider streaming/tool-call support in `libs/llm/openrouter.mojo` and app-owned tool orchestration in `src/main.mojo`, but still needs safety controls and a cleaner provider-agnostic agent abstraction.

---

## Milestone 3: Session Management

**Recommended next milestone.** Now that transport, JSON, streaming, tools, and structured in-memory history exist, persistent sessions are the next most valuable foundational step.

**Goal:** Persist conversations and support resuming.

### Status

**Started.** A structured in-memory session/message abstraction now exists in `libs/llm/history.mojo`, but persistence and resume flows are not implemented yet.

### Tasks

- [x] **Structured in-memory history** — `SessionMessage` / `SessionHistory`
  - [x] User/system/assistant/tool result messages
  - [x] Assistant tool-call message support
  - [x] Serialization into provider-compatible message payloads
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

## Milestone 4: Tool Safety & Sandboxing

**Recommended after persistent sessions.** The tool loop works, but before a broader user-facing CLI/TUI, modex should add guardrails around filesystem and shell access.

### Tasks

- [ ] **Path restrictions** — Constrain read/write/edit to allowed roots
- [ ] **Bash permission model** — Allow/deny model for shell execution
- [ ] **Safer write/edit behavior** — Add overwrite/replace safeguards where needed
- [ ] **Tool confirmation hooks** — Support prompting/approval for risky operations
- [ ] **Configurable policy** — Project/global safety settings

### Deliverable

A usable coding-agent loop with basic safety boundaries suitable for wider interactive use.

---

## Milestone 5: Agent Core Extraction

**Recommended after safety work.** The current multi-turn loop lives at the app layer (`src/main.mojo`) on top of `OpenRouter`; extract it into a provider-agnostic agent/session layer once persistence and safety needs are clearer.

### Tasks

- [ ] **Provider-agnostic agent loop** — Extract prompt/tool/result orchestration from app code into a reusable agent layer
- [ ] **Generic message/session model** — Reuse `SessionHistory` as the core conversation abstraction
- [ ] **Tool registry abstraction** — Go beyond the current built-in dispatcher
- [ ] **Agent events/hooks** — Turn start/end, tool call/result, stream events
- [ ] **Provider adapter boundary** — Keep provider-specific transport/parsing separate from agent policy

### Deliverable

A clean agent core that can work across OpenRouter and future providers.

---

## Milestone 6: Terminal UI (TUI)

**Goal:** Interactive terminal interface with editor, chat display, and keyboard navigation.

### Status

**Not started as a full TUI.** A minimal colored stdin/stdout REPL now exists in `src/main.mojo`, and reusable ANSI helpers live in `libs/style/`, but there is no raw-mode/editor-driven terminal UI yet.

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

## Milestone 7: Multi-Provider Support

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

## Milestone 8: Context & Customization

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

## Milestone 9: Extensibility

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

## Milestone 10: Advanced Features

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

- **~~No HTTP client~~** — ✅ Solved: native libc socket FFI works (`libs/http_client/`)
- **~~No JSON parser~~** — ✅ Solved for current needs: native `libs/json/` now handles provider/tool-loop JSON
- **No async/await** — Mojo has no async runtime; streaming is currently blocking I/O
- **No dynamic module loading** — Extensions can't be loaded at runtime natively
- **String API in flux** — Nightly changes frequently: `s[i]` requires `byte=` keyword, slicing returns `StringSlice` (needs `String()` wrapping), `@value` removed, `alloc` is a free function, move init uses `deinit take` syntax. Track nightly changes carefully.

**Strategy:** Build native implementations in `libs/` where feasible (HTTP, TLS, SSE, JSON). Use Python interop pragmatically for file I/O, subprocess execution, and other ecosystem gaps until native replacements are justified.

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
- [x] Callback streaming in `OpenRouter`
- [ ] Token-by-token display in a TUI

### 5. TLS/HTTPS

- [x] OpenSSL `libssl` / `libcrypto` FFI implemented
- [x] HTTPS requests working against OpenRouter and other hosts
- [x] Shared chunked transfer decoding extracted and used by streaming paths
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
│   │   ├── __init__.mojo            #    Exports: HttpClient, HttpHeader, HttpResponse, chunked helpers
│   │   ├── chunked.mojo             #    Shared chunked transfer decoding
│   │   ├── client.mojo              #    HTTP requests, SSE fetch
│   │   ├── net.mojo                 #    Socket FFI: TcpSocket, resolve_host()
│   │   ├── response.mojo            #    Response parser: status, headers, body
│   │   └── tls.mojo                 #    OpenSSL-based TLS socket
│   │
│   ├── sse/                         # ✅ implemented
│   │   ├── __init__.mojo            #    Exports: SseParser, SseEvent
│   │   └── parser.mojo              #    Incremental SSE parser
│   │
│   ├── json/                        # ✅ implemented
│   │   ├── __init__.mojo            #    Exports: parse_json, JsonValue, serializer helpers
│   │   ├── parser.mojo              #    JSON token/value boundary parsing
│   │   ├── serializer.mojo          #    JSON builders/escaping
│   │   └── value.mojo               #    JSON value view/navigation
│   │
│   ├── llm/                         # ✅ substantially implemented
│   │   ├── __init__.mojo            #    Exports: OpenRouter client, history, shared types
│   │   ├── history.mojo             #    SessionHistory / SessionMessage abstraction
│   │   ├── openrouter.mojo          #    OpenRouter streaming client + tool-call primitives
│   │   └── types.mojo               #    Shared LLM/provider structs
│   │
│   ├── style/                       # ✅ implemented (minimal ANSI styling helpers)
│   │   └── __init__.mojo
│   │
│   ├── tools/                       # ✅ implemented (minimal, Python-backed execution)
│   │   ├── __init__.mojo
│   │   ├── bash.mojo
│   │   ├── edit.mojo
│   │   ├── read.mojo
│   │   ├── tool.mojo
│   │   └── write.mojo
│   │
│   └── tui/                         # planned
│
├── experiments/                     # Standalone experiments & spikes
│   ├── http_client.mojo             #    Python interop HTTP client
│   ├── http_client_native.mojo      #    Native libc socket HTTP client
│   ├── openrouter_builtin_tool_loop.mojo       # Generic built-in tool loop
│   ├── openrouter_builtin_tool_loop_callback.mojo  # Callback generic built-in tool loop
│   ├── openrouter_read_tool_loop.mojo          # Minimal read-tool loop
│   ├── openrouter_stream.mojo       #    Collected OpenRouter streaming
│   ├── openrouter_stream_callback.mojo  #    Callback-based OpenRouter streaming
│   ├── openrouter_tool_calls.mojo   #    Streamed tool-call parsing demo
│   └── sse_parser.mojo              #    Standalone SSE parser demo
│
└── tests/                           # Lightweight test runner + test modules
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
- **Python `requests`** — For Python interop HTTP (pixi dependency, mainly retained for early experiments)
- **libc** — For native sockets, termios, subprocess (via Mojo FFI, no extra install)
- **OpenSSL** — Used via FFI/runtime loading for native HTTPS/TLS

---

## MVP Definition (Milestones 1-3)

The minimum viable product is a CLI that:

1. Takes a user prompt
2. Sends it through OpenRouter with tool definitions
3. Streams the response
4. Executes tool calls (read, write, edit, bash)
5. Loops until the LLM stops calling tools
6. Prints the final response

This is now largely achieved in experiment form and a minimal stdin/stdout REPL in `src/main.mojo`. The main remaining gaps for a cleaner MVP are persistent sessions, safety controls, and a more provider-agnostic agent core.

### Recommended implementation order from here

1. **Persistent sessions**
2. **Tool safety / sandboxing**
3. **Provider-agnostic agent core extraction**
4. **TUI**
5. **Multi-provider support**

---

## Resolved Questions

1. **~~Mojo version pinning~~** — Tracking nightly (`max = "*"` from `max-nightly` channel). Pin in `mojoproject.toml` if stability needed.
2. **~~Python interop overhead~~** — Negligible for network I/O. Native libc FFI also works (proven in experiments).
3. **~~Project structure~~** — `libs/` for extractable packages, `src/` for modex app. Each lib is self-contained with `__init__.mojo`.
4. **~~TLS/HTTPS~~** — Implemented via OpenSSL FFI in `libs/http_client/tls.mojo`.
5. **~~Initial provider~~** — OpenRouter implemented first, including streaming and tool-call parsing.
6. **~~Structured conversation abstraction~~** — `SessionHistory` / `SessionMessage` implemented and used by tool loops.
7. **~~Native JSON~~** — `libs/json/` implemented and wired into provider/tool parsing and serialization.
8. **~~Minimal CLI styling layer~~** — `libs/style/` extracted for reusable ANSI terminal styling helpers.

## Open Questions

1. **Agent core extraction** — When should the current app-level tool loop move into a provider-agnostic agent/session layer?
2. **Persistent session format** — Should session files be compatible with pi? Same tree/message schema?
3. **Extension model** — Should extensions be Python scripts, compiled Mojo packages, or IPC-based plugins?
4. **Licensing** — MIT to match pi?
5. **IPv6 support** — Add full `sockaddr_in6` + multi-address fallback now, or defer until after persistent sessions/safety work?
6. **JSON completeness** — How far should `libs/json/` go beyond current practical needs (Unicode, floats, full DOM, performance)?
