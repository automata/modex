from llm import OpenRouterChunk, OpenRouterClient
from os import getenv
from python import Python
from style import ansi_cyan, ansi_dim, ansi_green, ansi_magenta, ansi_yellow, style


fn system_prompt() -> String:
    return (
        "You are modex, a minimal AI coding agent running in a local repository. "
        "Be concise, practical, and action-oriented. "
        "Use the available tools when needed to inspect files, edit code, write files, or run shell commands. "
        "Prefer reading files before changing them. "
        "Do not invent file contents you have not inspected when inspection is important. "
        "When using edit, make precise replacements. "
        "When using bash, keep commands focused and relevant. "
        "After using tools, summarize what you changed or found clearly."
    )


fn on_chunk(chunk: OpenRouterChunk):
    if len(chunk.delta) > 0:
        print(chunk.delta, end="")
        return

    if chunk.has_tool_call():
        if len(chunk.tool_call_name) > 0:
            print(
                "\n" + style("[tool]", ansi_yellow(), bold=True) + " " + style(chunk.tool_call_name, ansi_magenta(), bold=True),
                end="",
            )
            if len(chunk.tool_call_arguments) > 0:
                print(" " + style(chunk.tool_call_arguments, dim=True), end="")
        elif len(chunk.tool_call_arguments) > 0:
            print(style(chunk.tool_call_arguments, dim=True), end="")
        return

    if chunk.finish_reason == "tool_calls":
        print()


fn _print_banner(model: String):
    print(style("modex 🔥", ansi_green(), bold=True), end="\n\n")
    print(style("Model:", ansi_cyan(), bold=True), model)
    print(style("Tools:", ansi_cyan(), bold=True), "read, write, edit, bash")
    print(style("Commands:", ansi_cyan(), bold=True), "/exit, /quit")


fn main() raises:
    var model = getenv("OPENROUTER_MODEL")
    if len(model) == 0:
        model = "openai/gpt-4o-mini"

    _print_banner(model)

    var client = OpenRouterClient.from_env()
    var py_builtins = Python.import_module("builtins")

    while True:
        var prompt = String(py_builtins.input(style("\n\n> ", ansi_green(), bold=True)))
        if len(prompt) == 0:
            continue
        if prompt == "/exit" or prompt == "/quit":
            print(style("bye", dim=True))
            break

        print()
        _ = client.run_with_default_builtin_tools_live(
            model,
            prompt,
            on_chunk,
            system_prompt=system_prompt(),
        )
