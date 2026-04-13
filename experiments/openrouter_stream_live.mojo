from llm import OpenRouterClient, OpenRouterChunk

fn on_chunk(chunk: OpenRouterChunk):
    if len(chunk.delta) > 0:
        print(chunk.delta, end="")

fn main() raises:
    var client = OpenRouterClient.from_env()
    client.stream_text_live(
        "openai/gpt-4o-mini",
        "Write a haiku about Mojo and coding agents.",
        on_chunk,
    )
    print()
