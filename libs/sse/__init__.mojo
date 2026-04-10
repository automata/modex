"""Server-Sent Events (SSE) parser.

Incremental parser for `text/event-stream` responses.

Example:
    from sse import SseParser

    fn main() raises:
        var parser = SseParser()
        var events = parser.feed("data: hello\n\n")
        for event in events:
            print(event.event_type, event.data)
"""

from .parser import SseEvent, SseParser
