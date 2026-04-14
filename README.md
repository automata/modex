# modex 🔥

A Mojo-based AI coding harness — a terminal coding agent inspired by
[pi](https://github.com/badlogic/pi-mono/tree/main/packages/coding-agent).

## Prerequisites

- **Linux x86_64** (other platforms: adjust `platforms` in
  `mojoproject.toml`)
- **curl** and **bash** (for pixi installer)

## Setup

### 1. Install pixi

[pixi](https://pixi.sh) is the package manager used to install and manage
Mojo.

```bash
curl -fsSL https://pixi.sh/install.sh | bash
```

Then restart your shell or run:

```bash
source ~/.bashrc
```

Verify:

```bash
pixi --version
```

### 2. Clone and install dependencies

```bash
git clone <repo-url> modex
cd modex
pixi install
```

This downloads Mojo nightly and all dependencies into the project's
`.pixi/` directory. Nothing is installed globally — everything is
self-contained.

### 3. Verify Mojo works

```bash
pixi run mojo --version
```

You should see something like:

```
Mojo 0.26.x.x.dev... (nightly)
```

## Development

### Run

```bash
pixi run run
```

This launches the current minimal colored coding-agent REPL backed by OpenRouter and the built-in tools.

### Build

```bash
pixi run build
```

Produces a `./modex` binary.

### Test

```bash
pixi run test
```

### Run Mojo commands directly

Use `pixi run` to run any Mojo command inside the environment:

```bash
pixi run mojo run src/main.mojo
pixi run mojo build src/main.mojo -o modex
pixi run mojo repl
```

### Enter the pixi shell

To get a shell with Mojo on your PATH (so you can run `mojo` directly
without `pixi run`):

```bash
pixi shell
mojo --version
mojo repl
```

## Experiments

### OpenRouter streaming

These experiments use the native `http_client` + `sse` + `json` +
`llm/openrouter` stack to stream completions from OpenRouter.

Set your API key:

```bash
export OPENROUTER_API_KEY=sk-or-...
```

Buffered streaming experiment:

```bash
pixi run mojo run -I libs experiments/openrouter_stream.mojo
```

Live callback streaming experiment:

```bash
pixi run mojo run -I libs experiments/openrouter_stream_live.mojo
```

Tool-calling experiment (parses streamed tool-call deltas and assembles full tool calls):

```bash
pixi run mojo run -I libs experiments/openrouter_tool_calls.mojo
```

Read-tool loop experiment (OpenRouter requests the `read` tool, modex executes it, then sends the tool result back and prints the final answer):

```bash
pixi run mojo run -I libs experiments/openrouter_read_tool_loop.mojo
```

Generic built-in tool loop experiment (currently supports `read`, `write`, `edit`, `bash` schemas and execution dispatch):

```bash
pixi run mojo run -I libs experiments/openrouter_builtin_tool_loop.mojo
```

Live callback version of the generic built-in tool loop:

```bash
pixi run mojo run -I libs experiments/openrouter_builtin_tool_loop_live.mojo
```

Expected output: a short streamed response or one or more parsed tool calls printed to the terminal.

### Other experiments

```bash
# Python interop HTTP client
pixi run mojo run -I libs experiments/http_client.mojo

# Native libc socket HTTP client
pixi run mojo run -I libs experiments/http_client_native.mojo

# Standalone SSE parser
pixi run mojo run -I libs experiments/sse_parser.mojo
```

## Project structure

```
modex/
├── mojoproject.toml          # Project config, dependencies, tasks
├── src/
│   └── main.mojo             # Entry point (imports from libs/)
├── libs/                     # Reusable Mojo packages (each extractable)
│   ├── http_client/          # Native HTTP/HTTPS client over libc + OpenSSL
│   │   ├── __init__.mojo     # Package exports
│   │   ├── chunked.mojo      # Shared chunked transfer decoding
│   │   ├── client.mojo       # HttpClient high-level API + SSE fetch helpers
│   │   ├── net.mojo          # Low-level socket FFI bindings
│   │   ├── response.mojo     # HTTP response parser
│   │   └── tls.mojo          # OpenSSL TLS socket
│   ├── sse/                  # Incremental Server-Sent Events parser
│   │   ├── __init__.mojo
│   │   └── parser.mojo
│   ├── json/                 # Native JSON parser + serializer
│   │   ├── __init__.mojo
│   │   ├── parser.mojo
│   │   ├── value.mojo
│   │   └── serializer.mojo
│   ├── llm/                  # LLM provider clients + shared history/types
│   │   ├── __init__.mojo
│   │   ├── history.mojo      # SessionHistory / SessionMessage
│   │   ├── openrouter.mojo   # OpenRouter streaming + tool loops
│   │   └── types.mojo        # Shared provider structs
│   ├── style/                # Minimal ANSI styling helpers for CLI output
│   │   └── __init__.mojo
│   └── tools/                # Built-in tool definitions + execution
│       ├── __init__.mojo
│       ├── bash.mojo
│       ├── edit.mojo
│       ├── read.mojo
│       ├── tool.mojo
│       └── write.mojo
├── experiments/              # Standalone experiments
│   ├── http_client.mojo
│   ├── http_client_native.mojo
│   ├── openrouter_stream.mojo
│   ├── openrouter_stream_live.mojo
│   ├── openrouter_tool_calls.mojo
│   ├── openrouter_read_tool_loop.mojo
│   ├── openrouter_builtin_tool_loop.mojo
│   ├── openrouter_builtin_tool_loop_live.mojo
│   └── sse_parser.mojo
├── tests/                    # Tests (pixi run test)
├── plan.md                   # Development roadmap
└── README.md                 # This file
```

### Extractable libraries

Each directory under `libs/` is a self-contained Mojo package that can be
extracted and published independently. They have their own `__init__.mojo`
with public exports and no dependencies on modex internals.

To use a lib in another project, copy the directory and add `-I <path>` to
your `mojo` commands (or add the parent directory to `MOJO_IMPORT_PATH`).

```mojo
// In any Mojo project with http_client on the import path:
from http_client import HttpClient

fn main() raises:
    var client = HttpClient()
    var resp = client.get("https://example.com/")
    print(resp.status_code, resp.body)
```

## Why Mojo nightly?

modex tracks Mojo nightly (`max = "*"` from the `max-nightly` channel) to
get the latest language features. Mojo is evolving fast — nightly gives us
access to the newest stdlib additions and bug fixes.

To pin to a specific version instead, edit `mojoproject.toml`:

```toml
[dependencies]
max = "==25.2.0.dev2025022405"
```

## Configuration

### API keys

Set your OpenRouter API key as an environment variable:

```bash
export OPENROUTER_API_KEY=sk-or-...
```

OpenRouter is the current initial provider for modex. It supports:
- buffered streaming
- live callback streaming
- streamed tool-call parsing
- tool-call assembly from partial streamed deltas
- structured in-memory conversation history via `SessionHistory`
- a minimal multi-turn `read` tool loop
- a generic built-in tool loop with `read`, `write`, `edit`, `bash`
- live callback streaming for the generic built-in tool loop
- native JSON parsing/serialization (no Python `json` dependency in `libs/`)
- shared chunked transfer decoding across buffered and live streaming paths

Current main limitations:
- the REPL is still minimal and does not preserve conversation history across turns yet
- tool execution is still minimal and largely Python-backed for file/subprocess operations
- no safety/sandboxing model yet
- no persistent sessions yet
- socket resolution is currently IPv4-only
- native JSON Unicode handling is still incomplete for some escape cases

Additional direct providers may be added later — see [plan.md](plan.md).

## Near-term roadmap

Recommended implementation order from here:

1. **Persistent sessions**
2. **Tool safety / sandboxing**
3. **Provider-agnostic agent core extraction**
4. **TUI**
5. **Multi-provider support**

See [plan.md](plan.md) for the full roadmap.

## License

MIT
