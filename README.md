# persevero

[![Package Version](https://img.shields.io/hexpm/v/persevero)](https://hex.pm/packages/persevero)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/persevero/)

Execute fallible operations multiple times.

## Installation

```sh
gleam add persevero@1
```

## Usage

A simple example:

```gleam
import gleam/http/request
import gleam/httpc
import gleam/io
import persevero

pub fn main() {
  let assert Ok(request) = request.to("https://www.apple.com")

  let response = {
    use <- persevero.execute(
      wait_stream: persevero.exponential_backoff(50, 2),
      allow: persevero.all_errors,
      mode: persevero.MaxAttempts(3),
    )

    httpc.send(request)
  }

  case response {
    Ok(response) if response.status == 200 -> io.debug("Give me #prawducks. 😃")
    _ -> io.debug("Guess I'll dev on Linux. 😔")
  }
}
```

A ridiculous example:

```gleam
import gleam/http/request
import gleam/httpc
import gleam/io
import persevero

pub fn main() {
  let assert Ok(request) = request.to("https://www.apple.com")

  let response =
    persevero.custom_backoff(wait_time: 1000, next_wait_time: fn(previous) {
      { previous + 100 } * 2
    })
    |> persevero.apply_multiplier(3)
    |> persevero.apply_jitter(20)
    |> persevero.apply_cap(10_000)
    |> persevero.apply_constant(7)
    |> persevero.execute(
      allow: fn(error) {
        case error {
          httpc.InvalidUtf8Response -> True
          _ -> False
        }
      },
      mode: persevero.MaxAttempts(10),
      operation: fn() { httpc.send(request) },
    )

  case response {
    Ok(response) if response.status == 200 -> io.debug("Give me #prawducks. 😃")
    _ -> io.debug("Guess I'll dev on Linux. 😔")
  }
}
```

Use raw [`yielder`](https://hexdocs.pm/gleam_yielder/gleam/yielder.html)s for
ultimate wait stream manipulation:

```gleam
use <- persevero.execute(
  wait_stream: yielder.range(1, 100) |> yielder.intersperse(0),
  allow: persevero.all_errors,
  mode: persevero.MaxAttempts(3),
)
```

Note that `persevero` generates a final wait stream with a 0 value at the
beginning, in the `execute` function, after all transformations to the stream
have been applied, so the first attempt will never sleep. You do not need to
account for this in your custom wait stream.

## Targets

`persevero` supports the Erlang target.
