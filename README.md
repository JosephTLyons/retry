# retry

[![Package Version](https://img.shields.io/hexpm/v/retry)](https://hex.pm/packages/gleam_retry)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/gleam_retry/)

Retry code that can fail.

## Usage

```sh
gleam add retry@1
```

```gleam
import gleam/int
import gleam/retry

pub type NetworkError {
  ServerDown
  Timeout(Int)
  InvalidStatusCode(Int)
  InvalidResponseBody(String)
}

pub fn main() {
  retry.new(max_attempts: 5, wait_time: 100)
  // Optional configuration
  |> retry.allow(allow: fn(error) {
    case error {
      InvalidStatusCode(code) if code >= 500 && code < 600 -> True
      Timeout(_) -> True
      _ -> False
    }
  })
  // Optional configuration
  |> retry.backoff(next_wait_time: int.multiply(_, 2))
  |> retry.execute(operation: fn() {
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

`retry` supports the Erlang target.
