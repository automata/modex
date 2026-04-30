from collections import List
from llm import OpenRouter, OpenRouterChunk

fn on_chunk(chunk: OpenRouterChunk):
    if len(chunk.delta) > 0:
        print(chunk.delta, end="")

fn main() raises:
    var client = OpenRouter.from_env()
    var messages = List[String]()
    messages.append("Write a haiku about Mojo and coding agents.")
    client.stream_messages("openai/gpt-4o-mini", messages, on_chunk)
    print()
