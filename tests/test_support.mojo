from python import Python


fn assert_true(condition: Bool, message: String) raises:
    if not condition:
        raise Error(message)


fn assert_false(condition: Bool, message: String) raises:
    if condition:
        raise Error(message)


fn assert_equal_string(actual: String, expected: String, message: String) raises:
    if actual != expected:
        raise Error(message + "\nexpected: " + expected + "\nactual:   " + actual)


fn assert_equal_int(actual: Int, expected: Int, message: String) raises:
    if actual != expected:
        raise Error(message + "\nexpected: " + String(expected) + "\nactual:   " + String(actual))


fn assert_contains(haystack: String, needle: String, message: String) raises:
    if haystack.find(needle) < 0:
        raise Error(message + "\nmissing: " + needle + "\nactual:  " + haystack)


fn ensure_clean_dir(path: String) raises:
    var py_os = Python.import_module("os")
    var py_shutil = Python.import_module("shutil")
    if py_os.path.exists(path):
        py_shutil.rmtree(path)
    py_os.makedirs(path, exist_ok=True)
