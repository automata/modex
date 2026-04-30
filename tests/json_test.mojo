from json import JsonArrayBuilder, JsonObjectBuilder, parse_json
from test_support import assert_equal_int, assert_equal_string, assert_false, assert_true


fn run_json_tests() raises -> Int:
    print("json: running")
    _parses_nested_values()
    _serializes_builders()
    _rejects_trailing_data()
    print("json: ok")
    return 3


fn _parses_nested_values() raises:
    var value = parse_json(
        " {\"name\":\"modex\",\"count\":2,\"items\":[true,null,\"x\"]} "
    )

    assert_equal_string(value.kind(), "object", "parse_json should return an object value")
    assert_equal_string(value.get("name").as_string(), "modex", "object string field should parse")
    assert_equal_int(value.get("count").as_int(), 2, "object int field should parse")
    assert_true(value.get("items").item(0).as_bool(), "array bool item should parse")
    assert_true(value.get("items").item(1).is_null(), "array null item should parse")
    assert_equal_string(value.get("items").item(2).as_string(), "x", "array string item should parse")
    assert_equal_int(value.get("items").len(), 3, "array length should match")
    assert_false(value.get("missing").exists, "missing object key should return a missing JsonValue")


fn _serializes_builders() raises:
    var obj = JsonObjectBuilder()
    obj.add_string("name", "modex")
    obj.add_int("count", 2)
    obj.add_bool("ok", True)
    obj.add_raw("items", "[1,2]")
    assert_equal_string(
        obj.finish(),
        "{\"name\":\"modex\",\"count\":2,\"ok\":true,\"items\":[1,2]}",
        "JsonObjectBuilder should emit compact JSON",
    )

    var arr = JsonArrayBuilder()
    arr.add_string("a")
    arr.add_raw("true")
    assert_equal_string(arr.finish(), "[\"a\",true]", "JsonArrayBuilder should emit compact JSON")


fn _rejects_trailing_data() raises:
    var raised = False
    try:
        _ = parse_json("true false")
    except e:
        raised = True
    assert_true(raised, "parse_json should reject trailing data")
