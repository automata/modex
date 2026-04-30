"""Structured session/message history for LLM conversations."""

from collections import List

from .types import OpenRouterToolCall


struct SessionMessage(Copyable):
    """A structured chat/session message."""

    var role: String
    var content: String
    var tool_call_id: String
    var tool_calls: List[OpenRouterToolCall]

    fn __init__(out self):
        self.role = ""
        self.content = ""
        self.tool_call_id = ""
        self.tool_calls = List[OpenRouterToolCall]()

    fn __init__(
        out self,
        role: String,
        content: String = "",
        tool_call_id: String = "",
        tool_calls: List[OpenRouterToolCall] = List[OpenRouterToolCall](),
    ):
        self.role = role
        self.content = content
        self.tool_call_id = tool_call_id
        self.tool_calls = tool_calls.copy()


struct SessionHistory:
    """In-memory session history with provider serialization helpers."""

    var messages: List[SessionMessage]

    fn __init__(out self):
        self.messages = List[SessionMessage]()

    fn append_message(mut self, message: SessionMessage):
        self.messages.append(message.copy())

    fn append_user(mut self, content: String):
        self.messages.append(SessionMessage("user", content))

    fn append_system(mut self, content: String):
        self.messages.append(SessionMessage("system", content))

    fn append_assistant_text(mut self, content: String):
        self.messages.append(SessionMessage("assistant", content))

    fn append_assistant_tool_calls(mut self, tool_calls: List[OpenRouterToolCall]):
        self.messages.append(SessionMessage("assistant", "", "", tool_calls))

    fn append_tool_result(mut self, tool_call_id: String, content: String):
        self.messages.append(SessionMessage("tool", content, tool_call_id))

