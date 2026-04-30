from collections import List
from llm import OpenRouter, SessionHistory

fn on_chunk(_chunk):
    pass

fn main() raises:
    var client = OpenRouter.from_env()
    var history = SessionHistory()
    history.append_user("Write a haiku about Mojo and coding agents.")
    var message = client.create("openai/gpt-4o-mini", history, on_chunk)
    print(message.content)
