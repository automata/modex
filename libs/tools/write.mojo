"""Minimal write tool."""

from python import Python


struct WriteTool:
    fn __init__(out self):
        pass

    fn name(self) -> String:
        return "write"

    fn description(self) -> String:
        return "Write content to a file, creating parent directories if needed. Parameters: path, content. Overwrites existing files."

    fn parameters_json_schema(self) -> String:
        return (
            "{"
            + "\"type\":\"object\","
            + "\"properties\":{"
            +   "\"path\":{\"type\":\"string\"},"
            +   "\"content\":{\"type\":\"string\"}"
            + "},"
            + "\"required\":[\"path\",\"content\"]"
            + "}"
        )


fn execute_write(path: String, content: String) raises -> String:
    var py_os = Python.import_module("os")
    var py_builtins = Python.import_module("builtins")

    var clean_path = path
    if len(clean_path) > 0 and clean_path.as_bytes()[0] == UInt8(ord("@")):
        clean_path = String(clean_path[1:])

    var cwd = String(py_os.getcwd())
    var abs_path = clean_path if py_os.path.isabs(clean_path) else String(py_os.path.join(cwd, clean_path))
    var parent = String(py_os.path.dirname(abs_path))
    if len(parent) > 0:
        py_os.makedirs(parent, exist_ok=True)

    var f = py_builtins.open(abs_path, "w", encoding="utf-8")
    f.write(content)
    f.close()
    return "Wrote " + String(len(content)) + " chars to " + clean_path
