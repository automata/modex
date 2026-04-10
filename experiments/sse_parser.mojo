from sse import SseParser

fn main() raises:
    var parser = SseParser()

    var chunks = [
        "event: message\n",
        "data: hello\n",
        "data: world\n\n",
        ": keepalive\n",
        "id: evt-2\nretry: 5000\ndata: second",
        " event line? no\n\n",
        "data: third\n\n",
    ]

    for i in range(len(chunks)):
        print("--- chunk", i, "---")
        print(chunks[i])
        var events = parser.feed(chunks[i])
        for event in events:
            print("type:", event.event_type)
            print("id:", event.id)
            print("data:", event.data)
            print("retry:", event.retry)
            print()
