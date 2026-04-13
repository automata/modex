"""Generic tool definitions and built-in tool dispatch."""

from collections import List
from json import parse_json

from .bash import BashTool, execute_bash
from .edit import EditTool, execute_edit
from .read import ReadTool, execute_read
from .write import WriteTool, execute_write


struct ToolDefinition(Copyable):
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


fn builtin_tool_definitions() -> List[ToolDefinition]:
    var defs = List[ToolDefinition]()

    var read_tool = ReadTool()
    defs.append(
        ToolDefinition(
            read_tool.name(),
            read_tool.description(),
            read_tool.parameters_json_schema(),
        )
    )

    var write_tool = WriteTool()
    defs.append(
        ToolDefinition(
            write_tool.name(),
            write_tool.description(),
            write_tool.parameters_json_schema(),
        )
    )

    var edit_tool = EditTool()
    defs.append(
        ToolDefinition(
            edit_tool.name(),
            edit_tool.description(),
            edit_tool.parameters_json_schema(),
        )
    )

    var bash_tool = BashTool()
    defs.append(
        ToolDefinition(
            bash_tool.name(),
            bash_tool.description(),
            bash_tool.parameters_json_schema(),
        )
    )

    return defs^


fn execute_builtin_tool(name: String, arguments_json: String) raises -> String:
    """Execute a built-in tool using a JSON arguments string."""
    var args = parse_json(arguments_json)

    if name == "read":
        var path = String()
        var path_val = args.get("path")
        if not path_val.is_missing():
            path = path_val.as_string()
        var offset = 1
        var offset_val = args.get("offset")
        if not offset_val.is_missing():
            offset = offset_val.as_int()
        var limit = 2000
        var limit_val = args.get("limit")
        if not limit_val.is_missing():
            limit = limit_val.as_int()
        return execute_read(path, offset, limit)

    if name == "write":
        var path = String()
        var path_val = args.get("path")
        if not path_val.is_missing():
            path = path_val.as_string()
        var content = String()
        var content_val = args.get("content")
        if not content_val.is_missing():
            content = content_val.as_string()
        return execute_write(path, content)

    if name == "edit":
        var path = String()
        var path_val = args.get("path")
        if not path_val.is_missing():
            path = path_val.as_string()
        var edits_val = args.get("edits")
        return execute_edit(path, edits_val.raw)

    if name == "bash":
        var command = String()
        var cmd_val = args.get("command")
        if not cmd_val.is_missing():
            command = cmd_val.as_string()
        var timeout = 0
        var timeout_val = args.get("timeout")
        if not timeout_val.is_missing():
            timeout = timeout_val.as_int()
        return execute_bash(command, timeout)

    return "Error: unsupported tool: " + name
