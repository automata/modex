from llm import OpenRouterClient, OpenRouterChunk

fn on_chunk(chunk: OpenRouterChunk):
    if len(chunk.delta) > 0:
        print(chunk.delta, end="")
    elif chunk.has_tool_call():
        print("\n[tool call] ", chunk.tool_call_name, " ", chunk.tool_call_arguments, sep="")
    elif len(chunk.finish_reason) > 0:
        print("\n[finish reason] ", chunk.finish_reason, sep="")

fn main() raises:
    var client = OpenRouterClient.from_env()
    var result = client.run_with_default_builtin_tools_live(
        "openai/gpt-4o-mini",
        "Read README.md using the available tools, then summarize modex in 2-3 sentences.",
        on_chunk,
    )
    print("\n\nFinal answer:\n" + result)
