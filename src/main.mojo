from collections import List
from io.io import _fdopen
from llm import OpenRouterChunk, OpenRouter, OpenRouterToolSpec, SessionHistory
from os import getenv
from style import ansi_cyan, ansi_dim, ansi_green, ansi_magenta, ansi_yellow, style
from sys import stdin
from tools import builtin_tool_definitions, execute_builtin_tool


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


fn _read_prompt() raises -> String:
    return _fdopen["r"](stdin).readline()


fn _default_tool_schemas() -> List[OpenRouterToolSpec]:
    var specs = List[OpenRouterToolSpec]()
    for tool in builtin_tool_definitions():
        specs.append(OpenRouterToolSpec(tool.name, tool.description, tool.parameters_json_schema))
    return specs^


fn _execute_tool_call(name: String, arguments: String) -> String:
    try:
        return execute_builtin_tool(name, arguments)
    except e:
        return "Error executing tool '" + name + "': " + String(e)


fn _run_turn_loop(
    client: OpenRouter,
    model: String,
    prompt: String,
    on_chunk: fn(OpenRouterChunk) -> NoneType,
    max_turns: Int = 6,
) raises -> String:
    var history = SessionHistory()
    history.append_system(system_prompt())
    history.append_user(prompt)

    var tools = _default_tool_schemas()

    for _turn in range(max_turns):
        var message = client.create(model, history, on_chunk, tools)

        if len(message.tool_calls) == 0:
            history.append_message(message)
            return message.content

        history.append_message(message)

        for call in message.tool_calls:
            var tool_result = _execute_tool_call(call.function_name, call.arguments)
            history.append_tool_result(call.id, tool_result)

    raise Error("tool loop exceeded max_turns without a final response")


fn main() raises:
    var model = getenv("OPENROUTER_MODEL")
    if len(model) == 0:
        model = "openai/gpt-4o-mini"

    _print_banner(model)

    var client = OpenRouter.from_env()

    while True:
        print(style("\n\n> ", ansi_green(), bold=True), end="")

        var prompt: String
        try:
            prompt = _read_prompt()
        except e:
            print()
            print(style("bye", dim=True))
            break

        if len(prompt) == 0:
            continue
        if prompt == "/exit" or prompt == "/quit":
            print(style("bye", dim=True))
            break

        print()
        _ = _run_turn_loop(client, model, prompt, on_chunk)
