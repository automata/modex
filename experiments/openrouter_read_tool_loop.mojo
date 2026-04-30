from collections import List
from llm import OpenRouter, OpenRouterChunk, OpenRouterToolSpec, SessionHistory
from tools import builtin_tool_definitions, execute_builtin_tool

fn on_chunk(chunk: OpenRouterChunk):
    pass

fn read_tool_schema() -> List[OpenRouterToolSpec]:
    var specs = List[OpenRouterToolSpec]()
    for tool in builtin_tool_definitions():
        if tool.name == "read":
            specs.append(OpenRouterToolSpec(tool.name, tool.description, tool.parameters_json_schema))
    return specs^

fn execute_tool_call(name: String, arguments: String) -> String:
    try:
        return execute_builtin_tool(name, arguments)
    except e:
        return "Error executing tool '" + name + "': " + String(e)

fn main() raises:
    var client = OpenRouter.from_env()
    var history = SessionHistory()
    history.append_user("Read README.md with the read tool, then summarize what modex is in 2-3 sentences.")

    var tools = read_tool_schema()

    for _turn in range(4):
        var message = client.create("openai/gpt-4o-mini", history, on_chunk, tools)

        if len(message.tool_calls) == 0:
            print(message.content)
            return

        history.append_message(message)
        for call in message.tool_calls:
            history.append_tool_result(call.id, execute_tool_call(call.function_name, call.arguments))

    raise Error("tool loop exceeded max turns")
