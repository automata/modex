from tools import execute_edit, execute_read, execute_write
from test_support import assert_contains, assert_equal_string, assert_true, ensure_clean_dir


fn run_tools_tests() raises -> Int:
    print("tools: running")
    _write_read_and_slice()
    _edit_replaces_exact_match()
    _read_missing_file_raises()
    print("tools: ok")
    return 3


fn _test_dir() raises -> String:
    var path = "tests/.tmp-tools"
    ensure_clean_dir(path)
    return path


fn _write_read_and_slice() raises:
    var dir_path = _test_dir()
    var path = dir_path + "/sample.txt"

    var write_result = execute_write(path, "line1\nline2\nline3")
    assert_contains(write_result, "Wrote ", "write tool should report bytes written")

    var out = execute_read(path, 2, 2)
    assert_equal_string(out, "line2\nline3", "read tool should honor offset and limit")


fn _edit_replaces_exact_match() raises:
    var dir_path = _test_dir()
    var path = dir_path + "/edit.txt"

    _ = execute_write(path, "alpha\nbeta")
    var edit_result = execute_edit(
        path,
        "[{\"oldText\":\"beta\",\"newText\":\"gamma\"}]",
    )
    assert_contains(edit_result, "Applied 1 edits", "edit tool should report applied edits")

    var out = execute_read(path)
    assert_equal_string(out, "alpha\ngamma", "edit tool should replace the matched text")


fn _read_missing_file_raises() raises:
    var raised = False
    try:
        _ = execute_read("tests/.tmp-tools/does-not-exist.txt")
    except e:
        raised = True
    assert_true(raised, "read tool should raise for a missing file")
