"""Experiment: HTTP client via Python interop (requests module)."""

from python import Python


fn main() raises:
    var requests = Python.import_module("requests")

    var url = "https://void.cc"
    print("GET", url)
    print("---")

    var response = requests.get(url, timeout=10)

    print("Status:", response.status_code)
    print("Content-Type:", response.headers.get("content-type", "unknown"))
    print("Content-Length:", len(String(response.text)), "chars")
    print("---")
    print(response.text)
