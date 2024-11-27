# persevero

[![Package Version](https://img.shields.io/hexpm/v/persevero)](https://hex.pm/packages/persevero)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/persevero/)

Execute fallible operations multiple times.

```txt
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
  Error(Timeout(int.random(5)))
}

pub fn main() {
  persevero.exponential_backoff(500, 2)
  |> persevero.apply_jitter(20)
  |> persevero.apply_cap(5000)
  |> persevero.execute(
    allow: fn(error) {
      case error {
        InvalidStatusCode(code) if code >= 500 && code < 600 -> True
        Timeout(_) -> True
        _ -> False
      }
    },
    max_attempts: 5,
    operation: network_request,
  )
  |> io.debug
  // Error(RetriesExhausted([Timeout(3), Timeout(4), Timeout(2), Timeout(3), Timeout(1)]))
}
```

## Targets

`persevero` supports the Erlang target.
