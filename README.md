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

A simple example:

```gleam
import persevero

pub fn main() {
  use <- persevero.execute(
    wait_stream: persevero.linear_backoff(50, 10),
    allow: fn(_) { True },
    max_attempts: 3,
  )
  fallible_operation()
}
```

A ridiculous example:

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
  Error(Timeout(int.random(5)))
}

pub fn main() {
  persevero.custom_backoff(wait_time: 1000, next_wait_time: fn(previous) {
    { previous + 100 } * 2
  })
  |> persevero.apply_multiplier(3)
  |> persevero.apply_jitter(20)
  |> persevero.apply_cap(10000)
  |> persevero.apply_constant(7)
  |> persevero.execute(
    allow: fn(error) {
      case error {
        InvalidStatusCode(code) if code >= 500 && code < 600 -> True
        Timeout(_) -> True
        _ -> False
      }
    },
    max_attempts: 10,
    operation: network_request,
  )
}
```

Note that `execute` takes in a `wait_stream` as its first parameter, which is
simply a `Yielder(Int)`. This means you can use the
[yielder](https://hexdocs.pm/gleam_yielder/gleam/yielder.html) package directly
if you want more control over wait time manipulation.

## Targets

`persevero` supports the Erlang target.
