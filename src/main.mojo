from http_client import HttpClient

fn main() raises:
    print("modex 🔥")
    print()

    var client = HttpClient()
    var resp = client.get("https://void.cc/")

    print("Status:", resp.status_code, resp.status_text)
    print("Server:", resp.header("Server"))
    print("Location:", resp.header("Location"))
    print()
    print("Body:")
    print(resp.body)
