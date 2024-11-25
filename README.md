# retry

[![Package Version](https://img.shields.io/hexpm/v/retry)](https://hex.pm/packages/retry)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/retry/)

A Gleam library retries code that can fail.

## Usage

```sh
gleam add retry@1
```

```gleam
import gleam/int
import retry

pub type NetworkError {
  ServerDown
  Timeout(Int)
  InvalidStatusCode(Int)
  InvalidResponseBody(String)
}

pub fn main() {
  retry.new()
  |> retry.max_attempts(max_attempts: 5)
  |> retry.wait(duration: 100)
  |> retry.allow(allow: fn(error) {
    case error {
      InvalidStatusCode(code) if code >= 500 && code < 600 -> True
      Timeout(_) -> True
      _ -> False
    }
  })
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
