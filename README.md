# retry

[![Package Version](https://img.shields.io/hexpm/v/retry)](https://hex.pm/packages/retry)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/retry/)

## Usage

```sh
gleam add retry@1
```

```gleam
import retry

pub type NetworkSuccessResponse {
  SuccessfulConnection
  ValidData
}

pub type NetworkErrorResponse {
  ConnectionTimeout
  ServerUnavailable
  InvalidResponse
}

pub fn flakey_function() -> Result(
  NetworkSuccessResponse,
  NetworkSuccessResponse,
) {
  // A function that produces unpredictable results
}

pub fn main() {
  use _ <- retry(times: 3, wait_time_in_ms: 100, allow: AllErrors)
  flakey_function()
}
```

## Targets

`retry` supports the Erlang target.
