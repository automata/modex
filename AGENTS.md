# AGENTS.md

## Read these first

- `docs/plan.md` — roadmap, architecture, current/planned milestones
- `docs/todo.md` — short current todo list
- `README.md` — setup, commands, project structure, current capabilities
- `src/main.mojo` — current app entrypoint and REPL behavior
- `libs/llm/openrouter.mojo` — current provider client and built-in tool loop
- `libs/llm/history.mojo` — in-memory conversation model
- `libs/tools/tool.mojo` — built-in tool registry/dispatch

## What this project is

`modex` is a Mojo-based AI coding harness inspired by pi. Current focus is a minimal coding agent with:

- OpenRouter chat completions
- native HTTP + SSE + JSON stack
- built-in tools: `read`, `write`, `edit`, `bash`
- minimal REPL now
- sessions, safety, and TUI next

## Code placement rules

- `libs/` = reusable, extractable Mojo packages only
- `src/` = modex app-specific behavior
- `experiments/` = standalone spikes/demos

If code is app policy, CLI behavior, config loading, session UX, or AGENTS handling, keep it out of `libs/`.

## Important constraints

- Keep changes small and targeted.
- Prefer existing patterns in the repo over inventing new abstractions.
- Preserve the layered design described in `docs/plan.md`.
- Do not claim planned features are already implemented.
- Update `README.md` and `docs/plan.md` if behavior or status meaningfully changes.

## Native Mojo vs Python interop

Follow the current codebase direction:

- prefer native Mojo in reusable/core layers such as `libs/http_client/`, `libs/sse/`, `libs/json/`
- Python interop is currently acceptable in tools and simple CLI paths
- do not rewrite working Python-backed pieces unless it directly supports the roadmap

## Validation

Use `pixi` commands from `README.md`:

- `pixi run run`
- `pixi run build`
- `pixi run test`

Run focused experiments from `README.md` when changing streaming/tool-loop behavior.

## If you touch these areas

- provider/tool loop logic → read `libs/llm/openrouter.mojo`
- message/session structure → read `libs/llm/history.mojo`
- built-in tools → read `libs/tools/tool.mojo` and the relevant file in `libs/tools/`
- app behavior → read `src/main.mojo`

## Heuristic

Choose the change that is:

1. aligned with `docs/plan.md`
2. smallest viable implementation
3. easiest to understand later
4. least damaging to `libs/` extractability
