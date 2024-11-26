# persevero

[![Package Version](https://img.shields.io/hexpm/v/persevero)](https://hex.pm/packages/persevero)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/persevero/)

Retry code that can fail.

## Usage

```sh
gleam add persevero@1
```

```gleam
import gleam/int
import persevero

pub type NetworkError {
  ServerDown
  Timeout(Int)
  InvalidStatusCode(Int)
  InvalidResponseBody(String)
}

pub fn main() {
  new(max_attempts: 5, wait_time: 1000, backoff: int.multiply(_, 2))
  // Optional configuration
  |> allow(allow: fn(error) {
    case error {
      InvalidStatusCode(code) if code >= 500 && code < 600 -> True
      Timeout(_) -> True
      _ -> False
    }
  })
  // Optional configuration
  |> max_wait_time(10_000)
  |> execute(operation: fn() {
    case int.random(4) {
      0 -> Error(ServerDown)
      1 -> Error(Timeout(5000))
      2 -> Error(InvalidStatusCode(503))
      3 -> Error(InvalidResponseBody("Malformed JSON"))
      _ -> Ok("Success!")
    }
  })
}
```

## Targets

`persevero` supports the Erlang target.
