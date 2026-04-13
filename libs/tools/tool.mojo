"""Generic tool definitions and built-in tool dispatch."""

from collections import List
from python import Python

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
    var py_json = Python.import_module("json")
    var args = py_json.loads(arguments_json)

    if name == "read":
        var path = String(args.get("path", ""))
        var offset = 1
        var limit = 2000
        try:
            offset = Int(py=args.get("offset", 1))
        except:
            pass
        try:
            limit = Int(py=args.get("limit", 2000))
        except:
            pass
        return execute_read(path, offset, limit)

    if name == "write":
        var path = String(args.get("path", ""))
        var content = String(args.get("content", ""))
        return execute_write(path, content)

    if name == "edit":
        var path = String(args.get("path", ""))
        var edits_py = args.get("edits", Python.list())
        var edits_json = String(py_json.dumps(edits_py))
        return execute_edit(path, edits_json)

    if name == "bash":
        var command = String(args.get("command", ""))
        var timeout = 0
        try:
            timeout = Int(py=args.get("timeout", 0))
        except:
            pass
        return execute_bash(command, timeout)

    return "Error: unsupported tool: " + name
