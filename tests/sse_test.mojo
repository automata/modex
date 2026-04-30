from sse import SseParser
from test_support import assert_equal_int, assert_equal_string


fn run_sse_tests() raises -> Int:
    print("sse: running")
    _parses_chunked_event()
    _joins_multiple_data_lines()
    _does_not_flush_unterminated_event()
    print("sse: ok")
    return 3


fn _parses_chunked_event() raises:
    var parser = SseParser()
    var events = parser.feed("event: update\ndata: hel")
    assert_equal_int(len(events), 0, "partial SSE chunk should not dispatch an event")

    events = parser.feed("lo\nid: evt-7\n\n")
    assert_equal_int(len(events), 1, "blank line should dispatch one SSE event")
    assert_equal_string(events[0].event_type, "update", "event type should parse")
    assert_equal_string(events[0].data, "hello", "event data should accumulate across chunks")
    assert_equal_string(events[0].id, "evt-7", "event id should parse")


fn _joins_multiple_data_lines() raises:
    var parser = SseParser()
    var events = parser.feed(": ignore me\ndata: first\ndata: second\n\n")
    assert_equal_int(len(events), 1, "two data lines should still produce one event")
    assert_equal_string(events[0].event_type, "message", "default event type should be message")
    assert_equal_string(events[0].data, "first\nsecond", "data lines should be joined with newlines")


fn _does_not_flush_unterminated_event() raises:
    var parser = SseParser()
    _ = parser.feed("data: almost there")
    var events = parser.finish()
    assert_equal_int(len(events), 0, "finish should not dispatch an unterminated event")
