"""Incremental SSE parser.

Implements the core Server-Sent Events line parsing model:
- blank line dispatches an event
- `data:` lines are joined with `\n`
- `event:` sets event type
- `id:` sets last-event-id
- `retry:` parses reconnection delay
- `:` comment lines are ignored
"""

from collections import List, Optional


struct SseEvent(Copyable):
    """A parsed SSE event."""

    var event_type: String
    var data: String
    var id: String
    var retry: Optional[Int]

    fn __init__(out self):
        self.event_type = "message"
        self.data = ""
        self.id = ""
        self.retry = Optional[Int]()

    fn __init__(
        out self,
        event_type: String,
        data: String,
        id: String = "",
        retry: Optional[Int] = Optional[Int](),
    ):
        self.event_type = event_type
        self.data = data
        self.id = id
        self.retry = retry


struct SseParser:
    """Incremental parser for Server-Sent Events streams."""

    var buffer: String
    var current_event_type: String
    var current_data: String
    var current_id: String
    var current_retry: Optional[Int]
    var last_event_id: String

    fn __init__(out self):
        self.buffer = ""
        self.current_event_type = ""
        self.current_data = ""
        self.current_id = ""
        self.current_retry = Optional[Int]()
        self.last_event_id = ""

    fn feed(mut self, chunk: String) raises -> List[SseEvent]:
        """Feed a new chunk into the parser and return parsed events."""
        self.buffer += chunk

        var events = List[SseEvent]()
        var start = 0

        while True:
            var line_end = self.buffer.find("\n", start)
            if line_end < 0:
                break

            var line = String(self.buffer[start:line_end])
            if len(line) > 0 and _ends_with_cr(line):
                line = String(line[: len(line) - 1])

            self._process_line(line, events)
            start = line_end + 1

        if start > 0:
            self.buffer = String(self.buffer[start:])

        return events^

    fn finish(mut self) raises -> List[SseEvent]:
        """Flush parser at end-of-stream.

        Per SSE behavior, a final event is only dispatched if terminated by a
        blank line. So this only processes a trailing partial line but does not
        force-dispatch an unfinished event.
        """
        var events = List[SseEvent]()
        if len(self.buffer) > 0:
            var line = self.buffer
            if _ends_with_cr(line):
                line = String(line[: len(line) - 1])
            self._process_line(line, events)
            self.buffer = ""
        return events^

    fn _process_line(mut self, line: String, mut events: List[SseEvent]):
        """Process one SSE line."""
        # Blank line dispatches an event.
        if len(line) == 0:
            self._dispatch_event(events)
            return

        # Comment line.
        if _starts_with_colon(line):
            return

        var colon = line.find(":")
        var field: String
        var value: String

        if colon < 0:
            field = line
            value = ""
        else:
            field = String(line[:colon])
            value = String(line[colon + 1 :])
            if len(value) > 0 and value.as_bytes()[0] == UInt8(ord(" ")):
                value = String(value[1:])

        if field == "event":
            self.current_event_type = value
        elif field == "data":
            if len(self.current_data) > 0:
                self.current_data += "\n"
            self.current_data += value
        elif field == "id":
            # Per SSE spec, ignore IDs containing NUL. Here we keep it simple
            # and accept all non-binary text.
            self.current_id = value
            self.last_event_id = value
        elif field == "retry":
            try:
                self.current_retry = Int(value)
            except:
                pass
        else:
            # Ignore unknown fields.
            pass

    fn _dispatch_event(mut self, mut events: List[SseEvent]):
        """Dispatch current buffered event, if any data exists."""
        if len(self.current_data) == 0:
            self.current_event_type = ""
            self.current_retry = Optional[Int]()
            return

        var event_type = (
            self.current_event_type if len(self.current_event_type) > 0 else "message"
        )
        var event_id = (
            self.current_id if len(self.current_id) > 0 else self.last_event_id
        )

        events.append(
            SseEvent(
                event_type,
                self.current_data,
                event_id,
                self.current_retry,
            )
        )

        self.current_event_type = ""
        self.current_data = ""
        self.current_id = ""
        self.current_retry = Optional[Int]()


fn _ends_with_cr(s: String) -> Bool:
    if len(s) == 0:
        return False
    var bytes = s.as_bytes()
    return bytes[len(s) - 1] == UInt8(ord("\r"))


fn _starts_with_colon(s: String) -> Bool:
    if len(s) == 0:
        return False
    return s.as_bytes()[0] == UInt8(ord(":"))
