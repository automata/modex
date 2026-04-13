"""Minimal edit tool using exact text replacement."""

from json import parse_json
from python import Python


struct EditTool:
    fn __init__(out self):
        pass

    fn name(self) -> String:
        return "edit"

    fn description(self) -> String:
        return "Apply exact text replacements to a file. Parameters: path, edits[{oldText,newText}]. Each oldText should match uniquely."

    fn parameters_json_schema(self) -> String:
        return (
            "{"
            + "\"type\":\"object\","
            + "\"properties\":{"
            +   "\"path\":{\"type\":\"string\"},"
            +   "\"edits\":{"
            +     "\"type\":\"array\","
            +     "\"items\":{"
            +       "\"type\":\"object\","
            +       "\"properties\":{"
            +         "\"oldText\":{\"type\":\"string\"},"
            +         "\"newText\":{\"type\":\"string\"}"
            +       "},"
            +       "\"required\":[\"oldText\",\"newText\"]"
            +     "}"
            +   "}"
            + "},"
            + "\"required\":[\"path\",\"edits\"]"
            + "}"
        )


fn execute_edit(path: String, edits_json: String) raises -> String:
    var py_os = Python.import_module("os")
    var py_builtins = Python.import_module("builtins")

    var clean_path = path
    if len(clean_path) > 0 and clean_path.as_bytes()[0] == UInt8(ord("@")):
        clean_path = String(clean_path[1:])

    var cwd = String(py_os.getcwd())
    var abs_path = clean_path if py_os.path.isabs(clean_path) else String(py_os.path.join(cwd, clean_path))
    var content = String(py_builtins.open(abs_path, "r", encoding="utf-8", errors="replace").read())

    var edits = parse_json(edits_json)
    var edit_count = edits.len()
    for i in range(edit_count):
        var edit = edits.item(i)
        var old_text = edit.get("oldText").as_string()
        var new_text = edit.get("newText").as_string()
        var occurrences = Int(py=content.count(old_text))
        if occurrences != 1:
            return "Error: oldText must match exactly once for edit " + String(i) + ", found " + String(occurrences)
        var idx = content.find(old_text)
        content = String(content[:idx]) + new_text + String(content[idx + len(old_text) :])

    var f = py_builtins.open(abs_path, "w", encoding="utf-8")
    f.write(content)
    f.close()
    return "Applied " + String(edit_count) + " edits to " + clean_path
