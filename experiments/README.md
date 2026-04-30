
## Experiments

### OpenRouter streaming

These experiments use the native `http_client` + `sse` + `json` +
`llm/openrouter` stack to stream completions from OpenRouter.

Set your API key:

```bash
export OPENROUTER_API_KEY=sk-or-...
```

Collected streaming experiment:

```bash
pixi run mojo run -I libs experiments/openrouter_stream.mojo
```

Callback streaming experiment:

```bash
pixi run mojo run -I libs experiments/openrouter_stream_callback.mojo
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

Callback version of the generic built-in tool loop:

```bash
pixi run mojo run -I libs experiments/openrouter_builtin_tool_loop_callback.mojo
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

