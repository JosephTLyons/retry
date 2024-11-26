# persevero

[![Package Version](https://img.shields.io/hexpm/v/persevero)](https://hex.pm/packages/persevero)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/persevero/)

Retry code that can fail.

```
⚠️ As we're still iterating and refining this pre-v1.0 library, the API may evolve to accommodate missing features and improvements.
```

## Usage

```sh
gleam add persevero@1
```

```gleam
import gleam/int
import gleam/io
import persevero

pub type NetworkError {
  ServerDown
  Timeout(Int)
  InvalidStatusCode(Int)
  InvalidResponseBody(String)
}

pub fn network_request() -> Result(String, NetworkError) {
  Error(Timeout(100))
}

pub fn main() {
  persevero.new(wait_time: 1000, backoff: int.multiply(_, 2))
  |> persevero.max_attempts(5)
  |> persevero.max_wait_time(10_000)
  |> persevero.execute(operation: network_request, allow: fn(error) {
    case error {
      InvalidStatusCode(code) if code >= 500 && code < 600 -> True
      Timeout(_) -> True
      _ -> False
    }
  })
  |> io.debug // Error(RetriesExhausted([Timeout(100), Timeout(100), Timeout(100), Timeout(100), Timeout(100)]))
}
```

## Targets

`persevero` supports the Erlang target.
