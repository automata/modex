from collections import List
from llm import OpenRouter, OpenRouterChunk, OpenRouterToolSpec, SessionHistory

fn on_chunk(_chunk: OpenRouterChunk):
    pass

fn main() raises:
    var client = OpenRouter.from_env()

    # Tool definitions are provider-side only for now. This experiment shows
    # how to send tool schemas and receive a structured assistant message with
    # assembled tool calls.
    var tools = List[OpenRouterToolSpec]()
    tools.append(
        OpenRouterToolSpec(
            "read",
            "Read a file from the current project.",
            "{\"type\":\"object\",\"properties\":{\"path\":{\"type\":\"string\",\"description\":\"Relative file path\"}},\"required\":[\"path\"]}",
        )
    )
    tools.append(
        OpenRouterToolSpec(
            "bash",
            "Run a shell command in the current project.",
            "{\"type\":\"object\",\"properties\":{\"command\":{\"type\":\"string\",\"description\":\"Command to execute\"}},\"required\":[\"command\"]}",
        )
    )

    var history = SessionHistory()
    history.append_user("Use the read tool to inspect README.md. Do not answer normally. If the file exists, call the tool.")
    var message = client.create("openai/gpt-4o-mini", history, on_chunk, tools)

    print("Assistant role:", message.role)
    if len(message.content) > 0:
        print("Content:", message.content)

    print()
    print("Tool calls:")
    var calls = message.tool_calls
    if len(calls) == 0:
        print("  (no tool calls returned by model)")
        print("  Tip: try a different model if this one chose not to call tools.")
    else:
        for call in calls:
            print("- index:", call.index)
            print("  id:", call.id)
            print("  name:", call.function_name)
            print("  arguments:", call.arguments)
