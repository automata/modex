### Extractable libraries

Each directory under `libs/` is a self-contained Mojo package that can be
extracted and published independently. They have their own `__init__.mojo`
with public exports and no dependencies on modex internals.

To use a lib in another project, copy the directory and add `-I <path>` to
your `mojo` commands (or add the parent directory to `MOJO_IMPORT_PATH`).

```mojo
// In any Mojo project with http_client on the import path:
from http_client import HttpClient

fn main() raises:
    var client = HttpClient()
    var resp = client.get("https://example.com/")
    print(resp.status_code, resp.body)
```

