from json_test import run_json_tests
from sse_test import run_sse_tests
from tools_test import run_tools_tests


fn main() raises:
    var total = 0
    total += run_json_tests()
    total += run_sse_tests()
    total += run_tools_tests()
    print("all tests passed (" + String(total) + ")")
