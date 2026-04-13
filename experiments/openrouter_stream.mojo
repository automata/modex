from llm import OpenRouterClient

fn main() raises:
    var client = OpenRouterClient.from_env()
    var chunks = client.stream_text(
        "openai/gpt-4o-mini",
        "Write a haiku about Mojo and coding agents.",
    )

    for chunk in chunks:
        if len(chunk.delta) > 0:
            print(chunk.delta, end="")

    print()
