# persevero

[![Package Version](https://img.shields.io/hexpm/v/persevero)](https://hex.pm/packages/persevero)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/persevero/)

Retry code that can fail.

⚠️ This library is pre-v1.0 and the API may change.

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

pub fn network_request() -> Result(String, NetworkError) {
  // ...
}

pub fn main() {
  persevero.new(max_attempts: 5, wait_time: 1000, backoff: int.multiply(_, 2))
  // Optional configuration
  |> persevero.allow(allow: fn(error) {
    case error {
      InvalidStatusCode(code) if code >= 500 && code < 600 -> True
      Timeout(_) -> True
      _ -> False
    }
  })
  // Optional configuration
  |> persevero.max_wait_time(10_000)
  |> persevero.execute(operation: network_request)
}
```

## Targets

`persevero` supports the Erlang target.
