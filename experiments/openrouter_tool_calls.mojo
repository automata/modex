from collections import List
from llm import OpenRouterClient, OpenRouterToolSpec, assemble_tool_calls

fn main() raises:
    var client = OpenRouterClient.from_env()

    # Tool definitions are provider-side only for now. This experiment shows
    # how to send tool schemas, parse streamed tool-call deltas, and assemble
    # complete tool calls from partial chunks.
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

    var chunks = client.stream_text_with_tools(
        "openai/gpt-4o-mini",
        "Use the read tool to inspect README.md. Do not answer normally. If the file exists, call the tool.",
        tools,
    )

    print("Streamed chunks:", len(chunks))
    print()

    for chunk in chunks:
        if len(chunk.delta) > 0:
            print("text delta:", chunk.delta)
        if chunk.has_tool_call():
            print("tool delta:")
            print("  index:", chunk.tool_call_index)
            print("  id:", chunk.tool_call_id)
            print("  name:", chunk.tool_call_name)
            print("  arguments delta:", chunk.tool_call_arguments)
        if len(chunk.finish_reason) > 0:
            print("finish reason:", chunk.finish_reason)

    print()
    print("Assembled tool calls:")
    var calls = assemble_tool_calls(chunks)
    if len(calls) == 0:
        print("  (no tool calls returned by model)")
        print("  Tip: try a different model if this one chose not to call tools.")
    else:
        for call in calls:
            print("- index:", call.index)
            print("  id:", call.id)
            print("  name:", call.function_name)
            print("  arguments:", call.arguments)
