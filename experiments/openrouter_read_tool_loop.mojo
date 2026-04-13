from llm import OpenRouterClient

fn main() raises:
    var client = OpenRouterClient.from_env()
    var result = client.run_with_read_tool(
        "openai/gpt-4o-mini",
        "Read README.md with the read tool, then summarize what modex is in 2-3 sentences.",
    )
    print(result)
