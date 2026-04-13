"""Minimal read tool.

Current implementation uses Python interop for path normalization and file I/O.
This keeps the tool simple while the rest of the transport/provider stack is
native Mojo.
"""

from collections import List
from python import Python

comptime DEFAULT_MAX_LINES = 2000
comptime DEFAULT_MAX_BYTES = 50 * 1024


struct ReadTool:
    """Read file contents from the current working directory."""

    fn __init__(out self):
        pass

    fn name(self) -> String:
        return "read"

    fn description(self) -> String:
        return (
            "Read file contents. Parameters: path (string), offset (1-indexed optional line number), "
            "limit (optional number of lines). Output is truncated to 2000 lines or 50KB."
        )

    fn parameters_json_schema(self) -> String:
        return (
            "{"
            + "\"type\":\"object\"," 
            + "\"properties\":{"
            +   "\"path\":{\"type\":\"string\",\"description\":\"File path relative to current directory\"},"
            +   "\"offset\":{\"type\":\"integer\",\"description\":\"1-indexed start line\"},"
            +   "\"limit\":{\"type\":\"integer\",\"description\":\"Maximum number of lines to read\"}"
            + "},"
            + "\"required\":[\"path\"]"
            + "}"
        )

    fn execute(self, path: String, offset: Int = 1, limit: Int = DEFAULT_MAX_LINES) raises -> String:
        return execute_read(path, offset, limit)


fn execute_read(path: String, offset: Int = 1, limit: Int = DEFAULT_MAX_LINES) raises -> String:
    """Execute the read tool and return text output."""
    var py_os = Python.import_module("os")
    var py_builtins = Python.import_module("builtins")

    var clean_path = path
    if len(clean_path) > 0 and clean_path.as_bytes()[0] == UInt8(ord("@")):
        clean_path = String(clean_path[1:])

    var cwd = String(py_os.getcwd())
    var abs_path: String
    if py_os.path.isabs(clean_path):
        abs_path = clean_path
    else:
        abs_path = String(py_os.path.join(cwd, clean_path))

    if not py_os.path.exists(abs_path):
        raise Error("File not found: " + clean_path)
    if py_os.path.isdir(abs_path):
        raise Error("Path is a directory: " + clean_path)

    var content = String(py_builtins.open(abs_path, "r", encoding="utf-8", errors="replace").read())
    return _slice_and_truncate(content, clean_path, offset, limit)


fn _slice_and_truncate(content: String, display_path: String, offset: Int, limit: Int) -> String:
    var lines = _split_lines(content)
    var start = 0
    if offset > 1:
        start = offset - 1
    var max_lines = DEFAULT_MAX_LINES
    if limit > 0:
        max_lines = limit
    var end = min(len(lines), start + max_lines)

    if start >= len(lines):
        return "[No content at requested offset for " + display_path + "]"

    var out = String()
    for i in range(start, end):
        out += lines[i]
        if i < end - 1:
            out += "\n"

    var truncated = False
    if len(out) > DEFAULT_MAX_BYTES:
        out = String(out[:DEFAULT_MAX_BYTES])
        truncated = True
    if end < len(lines):
        truncated = True

    if truncated:
        out += "\n\n[Output truncated]"
    return out


fn _split_lines(s: String) -> List[String]:
    var lines = List[String]()
    var pos = 0
    while pos <= len(s):
        var next_nl = s.find("\n", pos)
        if next_nl < 0:
            lines.append(String(s[pos:]))
            break
        lines.append(String(s[pos:next_nl]))
        pos = next_nl + 1
    return lines^
