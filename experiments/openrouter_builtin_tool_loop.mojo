from llm import OpenRouterClient

fn main() raises:
    var client = OpenRouterClient.from_env()
    var result = client.run_with_default_builtin_tools(
        "openai/gpt-4o-mini",
        "Read README.md using the available tools, then summarize modex in 2-3 sentences.",
    )
    print(result)
