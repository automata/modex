"""Minimal bash tool."""

from python import Python, PythonObject

comptime DEFAULT_MAX_BYTES = 50 * 1024
comptime DEFAULT_MAX_LINES = 2000


struct BashTool:
    fn __init__(out self):
        pass

    fn name(self) -> String:
        return "bash"

    fn description(self) -> String:
        return "Execute a shell command in the current working directory. Parameters: command, timeout (optional seconds). Output is truncated to 2000 lines or 50KB."

    fn parameters_json_schema(self) -> String:
        return (
            "{"
            + "\"type\":\"object\","
            + "\"properties\":{"
            +   "\"command\":{\"type\":\"string\"},"
            +   "\"timeout\":{\"type\":\"integer\"}"
            + "},"
            + "\"required\":[\"command\"]"
            + "}"
        )


fn execute_bash(command: String, timeout: Int = 0) raises -> String:
    var subprocess = Python.import_module("subprocess")
    try:
        var result: PythonObject
        if timeout > 0:
            result = subprocess.run(
                command,
                shell=True,
                text=True,
                capture_output=True,
                timeout=timeout,
            )
        else:
            result = subprocess.run(
                command,
                shell=True,
                text=True,
                capture_output=True,
            )
        var output = String(result.stdout) + String(result.stderr)
        output = _truncate(output)
        return output + "\n\n[exit code: " + String(Int(py=result.returncode)) + "]"
    except e:
        return "Error executing bash command: " + String(e)


fn _truncate(s: String) -> String:
    var out = s
    var truncated = False
    if len(out) > DEFAULT_MAX_BYTES:
        out = String(out[:DEFAULT_MAX_BYTES])
        truncated = True
    var lines = 0
    for i in range(len(out)):
        if out.as_bytes()[i] == UInt8(ord("\n")):
            lines += 1
            if lines >= DEFAULT_MAX_LINES:
                out = String(out[:i])
                truncated = True
                break
    if truncated:
        out += "\n[Output truncated]"
    return out
