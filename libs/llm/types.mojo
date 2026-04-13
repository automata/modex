"""Shared LLM/provider types."""


struct OpenRouterToolSpec(Copyable):
    """A function tool definition for OpenRouter/OpenAI-compatible APIs."""

    var name: String
    var description: String
    var parameters_json_schema: String

    fn __init__(out self):
        self.name = ""
        self.description = ""
        self.parameters_json_schema = "{}"

    fn __init__(
        out self,
        name: String,
        description: String,
        parameters_json_schema: String,
    ):
        self.name = name
        self.description = description
        self.parameters_json_schema = parameters_json_schema


struct OpenRouterToolCall(Copyable):
    """A streamed or assembled tool call."""

    var index: Int
    var id: String
    var function_name: String
    var arguments: String

    fn __init__(out self):
        self.index = -1
        self.id = ""
        self.function_name = ""
        self.arguments = ""

    fn __init__(
        out self,
        index: Int,
        id: String = "",
        function_name: String = "",
        arguments: String = "",
    ):
        self.index = index
        self.id = id
        self.function_name = function_name
        self.arguments = arguments


struct OpenRouterChunk(Copyable):
    """One streamed chunk from OpenRouter."""

    var delta: String
    var finish_reason: String
    var raw_json: String
    var tool_call_index: Int
    var tool_call_id: String
    var tool_call_name: String
    var tool_call_arguments: String

    fn __init__(out self):
        self.delta = ""
        self.finish_reason = ""
        self.raw_json = ""
        self.tool_call_index = -1
        self.tool_call_id = ""
        self.tool_call_name = ""
        self.tool_call_arguments = ""

    fn __init__(
        out self,
        delta: String,
        finish_reason: String = "",
        raw_json: String = "",
        tool_call_index: Int = -1,
        tool_call_id: String = "",
        tool_call_name: String = "",
        tool_call_arguments: String = "",
    ):
        self.delta = delta
        self.finish_reason = finish_reason
        self.raw_json = raw_json
        self.tool_call_index = tool_call_index
        self.tool_call_id = tool_call_id
        self.tool_call_name = tool_call_name
        self.tool_call_arguments = tool_call_arguments

    fn has_tool_call(self) -> Bool:
        return self.tool_call_index >= 0
