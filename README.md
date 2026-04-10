# modex 🔥

A Mojo-based AI coding harness — a terminal coding agent inspired by [pi](https://github.com/badlogic/pi-mono/tree/main/packages/coding-agent).

## Prerequisites

- **Linux x86_64** (other platforms: adjust `platforms` in `mojoproject.toml`)
- **curl** and **bash** (for pixi installer)

## Setup

### 1. Install pixi

[pixi](https://pixi.sh) is the package manager used to install and manage Mojo.

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

This downloads Mojo nightly and all dependencies into the project's `.pixi/` directory.
Nothing is installed globally — everything is self-contained.

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

## Project structure

```
modex/
├── mojoproject.toml       # Project config, dependencies, tasks
├── src/
│   └── main.mojo          # Entry point (imports from libs/)
├── libs/                  # Reusable Mojo packages (each extractable)
│   └── http_client/       # HTTP/1.1 client over libc sockets
│       ├── __init__.mojo   # Package exports
│       ├── client.mojo     # HttpClient high-level API
│       ├── net.mojo        # Low-level socket FFI bindings
│       └── response.mojo   # HTTP response parser
├── experiments/           # Standalone experiments
├── tests/                 # Tests (pixi run test)
├── plan.md                # Development roadmap
└── README.md              # This file
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
    var resp = client.get("http://example.com/")
    print(resp.status_code, resp.body)
```

## Why Mojo nightly?

modex tracks Mojo nightly (`max = "*"` from the `max-nightly` channel) to get
the latest language features. Mojo is evolving fast — nightly gives us access to the
newest stdlib additions and bug fixes.

To pin to a specific version instead, edit `mojoproject.toml`:

```toml
[dependencies]
max = "==25.2.0.dev2025022405"
```

## Configuration

### API keys

Set your LLM provider API key as an environment variable:

```bash
export ANTHROPIC_API_KEY=sk-ant-...
```

(More providers coming — see [plan.md](plan.md))

## License

MIT
