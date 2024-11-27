import gleam/int
import gleam/option.{None, Some}
import gleeunit
import gleeunit/should
import list_extensions.{at}
import persevero.{type RetryData, RetriesExhausted, RetryData, UnallowedError}

pub fn main() {
  gleeunit.main()
}

type MockNetworkSuccessResponse {
  SuccessfulConnection
  ValidData
}

type MockNetworkErrorResponse {
  ConnectionTimeout
  ServerUnavailable
  InvalidResponse
}

pub fn retry_exhausts_all_attempts_and_fails_with_no_backoff_test() {
  let times = 3
  let result_returning_function =
    result_returning_function(times: times, results: [
      // 1, wait 0
      Error(ConnectionTimeout),
      // 2, wait 100
      Error(ServerUnavailable),
      // 3, wait 100
      // error
      Error(InvalidResponse),
    ])

  persevero.no_backoff()
  |> persevero.execute_with_wait(
    wait_function: fake_wait,
    allow: fn(_) { True },
    max_attempts: times,
    operation: result_returning_function,
  )
  |> should.equal(
    RetryData(
      result: Error(
        RetriesExhausted([ConnectionTimeout, ServerUnavailable, InvalidResponse]),
      ),
      wait_times: [0, 0, 0],
    ),
  )
}

pub fn retry_exhausts_all_attempts_and_fails_with_constant_backoff_test() {
  let times = 3
  let result_returning_function =
    result_returning_function(times: times, results: [
      // 1, wait 0
      Error(ConnectionTimeout),
      // 2, wait 100
      Error(ServerUnavailable),
      // 3, wait 100
      // error
      Error(InvalidResponse),
    ])

  persevero.constant_backoff(100)
  |> persevero.execute_with_wait(
    wait_function: fake_wait,
    allow: fn(_) { True },
    max_attempts: times,
    operation: result_returning_function,
  )
  |> should.equal(
    RetryData(
      result: Error(
        RetriesExhausted([ConnectionTimeout, ServerUnavailable, InvalidResponse]),
      ),
      wait_times: [0, 100, 100],
    ),
  )
}

pub fn negative_retry_attempts_returns_retries_exhausted_error_test() {
  let times = -1
  let result_returning_function =
    result_returning_function(times: times, results: [
      Error(ConnectionTimeout),
      Error(ServerUnavailable),
      Error(InvalidResponse),
    ])

  persevero.constant_backoff(100)
  |> persevero.execute_with_wait(
    wait_function: fake_wait,
    allow: fn(_) { True },
    max_attempts: times,
    operation: result_returning_function,
  )
  |> should.equal(
    RetryData(result: Error(RetriesExhausted([])), wait_times: []),
  )
}

pub fn no_retry_attempts_returns_retries_exhausted_error_test() {
  let times = 0
  let result_returning_function =
    result_returning_function(times: times, results: [
      Error(ConnectionTimeout),
      Error(ServerUnavailable),
      Error(InvalidResponse),
    ])

  persevero.constant_backoff(100)
  |> persevero.execute_with_wait(
    wait_function: fake_wait,
    allow: fn(_) { True },
    max_attempts: times,
    operation: result_returning_function,
  )
  |> should.equal(
    RetryData(result: Error(RetriesExhausted([])), wait_times: []),
  )
}

pub fn one_retry_attempts_returns_retries_exhausted_error_test() {
  let times = 1
  let result_returning_function =
    result_returning_function(times: times, results: [
      Error(ConnectionTimeout),
      Error(ServerUnavailable),
      Error(InvalidResponse),
    ])

  persevero.constant_backoff(100)
  |> persevero.execute_with_wait(
    wait_function: fake_wait,
    allow: fn(_) { True },
    max_attempts: times,
    operation: result_returning_function,
  )
  |> should.equal(
    RetryData(result: Error(RetriesExhausted([ConnectionTimeout])), wait_times: [
      0,
    ]),
  )
}

pub fn retry_exhausts_all_attempts_and_fails_test() {
  let times = 3
  let result_returning_function =
    result_returning_function(times: times, results: [
      // 1, wait 0
      Error(ConnectionTimeout),
      // 2, wait 100
      Error(ServerUnavailable),
      // 3, wait 100
      // error
      Error(InvalidResponse),
    ])

  persevero.constant_backoff(100)
  |> persevero.execute_with_wait(
    wait_function: fake_wait,
    allow: fn(_) { True },
    max_attempts: times,
    operation: result_returning_function,
  )
  |> should.equal(
    RetryData(
      result: Error(
        RetriesExhausted([ConnectionTimeout, ServerUnavailable, InvalidResponse]),
      ),
      wait_times: [0, 100, 100],
    ),
  )
}

pub fn retry_fails_on_non_allowed_error_test() {
  let times = 3
  let result_returning_function =
    result_returning_function(times: times, results: [
      // 1, wait 0
      Error(ConnectionTimeout),
      // 2, wait 100
      // error
      Error(ServerUnavailable),
      // Doesn't reach
      Error(InvalidResponse),
      Ok(SuccessfulConnection),
    ])

  persevero.constant_backoff(100)
  |> persevero.execute_with_wait(
    wait_function: fake_wait,
    allow: fn(error) {
      case error {
        ConnectionTimeout | InvalidResponse -> True
        _ -> False
      }
    },
    max_attempts: times,
    operation: result_returning_function,
  )
  |> should.equal(
    RetryData(result: Error(UnallowedError(ServerUnavailable)), wait_times: [
      0, 100,
    ]),
  )
}

pub fn retry_succeeds_on_allowed_errors_test() {
  let times = 4
  let result_returning_function =
    result_returning_function(times: times, results: [
      // 1, wait 0
      Error(ConnectionTimeout),
      // 2, wait 100
      Error(ServerUnavailable),
      // 3, wait 100
      // succeed
      Ok(SuccessfulConnection),
      // Doesn't reach
      Error(InvalidResponse),
    ])

  persevero.constant_backoff(100)
  |> persevero.execute_with_wait(
    wait_function: fake_wait,
    allow: fn(error) {
      case error {
        ConnectionTimeout | ServerUnavailable -> True
        _ -> False
      }
    },
    max_attempts: times,
    operation: result_returning_function,
  )
  |> should.equal(
    RetryData(result: Ok(SuccessfulConnection), wait_times: [0, 100, 100]),
  )
}

pub fn retry_succeeds_when_all_errors_are_allowed_test() {
  let times = 4
  let result_returning_function =
    result_returning_function(times: times, results: [
      // 1, wait 0
      Error(ConnectionTimeout),
      // 2, wait 100
      Error(ServerUnavailable),
      // 3, wait 100
      Error(InvalidResponse),
      // 4, wait 100
      // succeed
      Ok(ValidData),
    ])

  persevero.constant_backoff(100)
  |> persevero.execute_with_wait(
    wait_function: fake_wait,
    allow: fn(_) { True },
    max_attempts: times,
    operation: result_returning_function,
  )
  |> should.equal(
    RetryData(result: Ok(ValidData), wait_times: [0, 100, 100, 100]),
  )
}

pub fn retry_succeeds_on_allowed_errors_apply_constant_and_multiplier_test() {
  let times = 4
  let result_returning_function =
    result_returning_function(times: times, results: [
      // 1, wait 0
      Error(ConnectionTimeout),
      // 2, wait 100
      Error(ServerUnavailable),
      // 3, wait 100
      // succeed
      Ok(SuccessfulConnection),
      // Doesn't reach
      Error(InvalidResponse),
    ])

  persevero.exponential_backoff(50, 2)
  |> persevero.apply_constant(1)
  |> persevero.apply_multiplier(3)
  |> persevero.apply_constant(1)
  |> persevero.execute_with_wait(
    wait_function: fake_wait,
    allow: fn(error) {
      case error {
        ConnectionTimeout | ServerUnavailable -> True
        _ -> False
      }
    },
    max_attempts: times,
    operation: result_returning_function,
  )
  |> should.equal(
    RetryData(result: Ok(SuccessfulConnection), wait_times: [0, 154, 304]),
  )
}

pub fn retry_succeeds_on_allowed_errors_apply_constant_after_cap_test() {
  let times = 4
  let result_returning_function =
    result_returning_function(times: times, results: [
      // 1, wait 0
      Error(ConnectionTimeout),
      // 2, wait 100
      Error(ServerUnavailable),
      // 3, wait 100
      // succeed
      Ok(SuccessfulConnection),
      // Doesn't reach
      Error(InvalidResponse),
    ])

  persevero.exponential_backoff(50, 2)
  |> persevero.apply_cap(100)
  |> persevero.apply_constant(3)
  |> persevero.execute_with_wait(
    wait_function: fake_wait,
    allow: fn(error) {
      case error {
        ConnectionTimeout | ServerUnavailable -> True
        _ -> False
      }
    },
    max_attempts: times,
    operation: result_returning_function,
  )
  |> should.equal(
    RetryData(result: Ok(SuccessfulConnection), wait_times: [0, 53, 103]),
  )
}

pub fn retry_succeeds_on_allowed_errors_apply_constant_before_cap_test() {
  let times = 4
  let result_returning_function =
    result_returning_function(times: times, results: [
      // 1, wait 0
      Error(ConnectionTimeout),
      // 2, wait 100
      Error(ServerUnavailable),
      // 3, wait 100
      // succeed
      Ok(SuccessfulConnection),
      // Doesn't reach
      Error(InvalidResponse),
    ])

  persevero.exponential_backoff(50, 2)
  |> persevero.apply_constant(3)
  |> persevero.apply_cap(100)
  |> persevero.execute_with_wait(
    wait_function: fake_wait,
    allow: fn(error) {
      case error {
        ConnectionTimeout | ServerUnavailable -> True
        _ -> False
      }
    },
    max_attempts: times,
    operation: result_returning_function,
  )
  |> should.equal(
    RetryData(result: Ok(SuccessfulConnection), wait_times: [0, 53, 100]),
  )
}

pub fn retry_with_exponential_backoff_test() {
  let times = 4
  let result_returning_function =
    result_returning_function(times: times, results: [
      // 1, wait 0
      Error(ConnectionTimeout),
      // 2, wait 100
      Error(ServerUnavailable),
      // 3, wait 200
      Error(InvalidResponse),
      // 4, wait 400
      // succeed
      Ok(ValidData),
    ])

  persevero.exponential_backoff(100, 2)
  |> persevero.execute_with_wait(
    wait_function: fake_wait,
    allow: fn(_) { True },
    max_attempts: times,
    operation: result_returning_function,
  )
  |> should.equal(
    RetryData(result: Ok(ValidData), wait_times: [0, 100, 200, 400]),
  )
}

pub fn retry_with_linear_backoff_test() {
  let times = 4
  let result_returning_function =
    result_returning_function(times: times, results: [
      // 1, wait 0
      Error(ConnectionTimeout),
      // 2, wait 100
      Error(ServerUnavailable),
      // 3, wait 200
      Error(InvalidResponse),
      // 4, wait 300
      // succeed
      Ok(ValidData),
    ])

  persevero.linear_backoff(100, 100)
  |> persevero.execute_with_wait(
    wait_function: fake_wait,
    allow: fn(_) { True },
    max_attempts: times,
    operation: result_returning_function,
  )
  |> should.equal(
    RetryData(result: Ok(ValidData), wait_times: [0, 100, 200, 300]),
  )
}

pub fn retry_with_custom_backoff_test() {
  let times = 4
  let result_returning_function =
    result_returning_function(times: times, results: [
      // 1, wait 0
      Error(ConnectionTimeout),
      // 2, wait 100
      Error(ServerUnavailable),
      // 3, wait 400
      Error(InvalidResponse),
      // 4, wait 1000
      // succeed
      Ok(ValidData),
    ])

  persevero.custom_backoff(100, fn(acc) { { acc + 100 } * 2 })
  |> persevero.execute_with_wait(
    wait_function: fake_wait,
    allow: fn(_) { True },
    max_attempts: times,
    operation: result_returning_function,
  )
  |> should.equal(
    RetryData(result: Ok(ValidData), wait_times: [0, 100, 400, 1000]),
  )
}

pub fn retry_with_backoff_succeeds_after_allowed_errors_test() {
  let times = 4
  let result_returning_function =
    result_returning_function(times: times, results: [
      // 1, wait 0
      Error(ConnectionTimeout),
      // 2, wait 100
      Error(ServerUnavailable),
      // 3, wait 300
      // succeed
      Ok(SuccessfulConnection),
      // Doesn't reach
      Error(InvalidResponse),
    ])

  persevero.exponential_backoff(100, 3)
  |> persevero.execute_with_wait(
    wait_function: fake_wait,
    allow: fn(error) {
      case error {
        ConnectionTimeout | ServerUnavailable -> True
        _ -> False
      }
    },
    max_attempts: times,
    operation: result_returning_function,
  )
  |> should.equal(
    RetryData(result: Ok(SuccessfulConnection), wait_times: [0, 100, 300]),
  )
}

pub fn retry_with_negative_wait_time_configuration_test() {
  let times = 4
  let result_returning_function =
    result_returning_function(times: times, results: [
      // 1, wait 0
      Error(ConnectionTimeout),
      // 2, wait 0
      Error(ServerUnavailable),
      // 3, wait 0
      // succeed
      Ok(SuccessfulConnection),
      // Doesn't reach
      Error(InvalidResponse),
    ])

  persevero.linear_backoff(-100, -1000)
  |> persevero.execute_with_wait(
    wait_function: fake_wait,
    allow: fn(_) { True },
    max_attempts: times,
    operation: result_returning_function,
  )
  |> should.equal(
    RetryData(result: Ok(SuccessfulConnection), wait_times: [0, 0, 0]),
  )
}

pub fn retry_with_cap_configuration_test() {
  let times = 5
  let result_returning_function =
    result_returning_function(times: times, results: [
      // 1, wait 0
      Error(ConnectionTimeout),
      // 2, wait 500
      Error(ServerUnavailable),
      // 3, wait 1000
      Error(ConnectionTimeout),
      // 4, wait 1000
      Error(ServerUnavailable),
      // 5, wait 1000
      // succeed
      Ok(SuccessfulConnection),
      // Doesn't reach
      Error(InvalidResponse),
    ])

  persevero.exponential_backoff(500, 2)
  |> persevero.apply_cap(1000)
  |> persevero.execute_with_wait(
    wait_function: fake_wait,
    allow: fn(error) {
      case error {
        ConnectionTimeout | ServerUnavailable -> True
        _ -> False
      }
    },
    max_attempts: times,
    operation: result_returning_function,
  )
  |> should.equal(
    RetryData(result: Ok(SuccessfulConnection), wait_times: [
      0, 500, 1000, 1000, 1000,
    ]),
  )
}

fn fake_wait(_) -> Nil {
  Nil
}

fn result_returning_function(
  times times: Int,
  results results: List(Result(a, b)),
) -> fn(Int) -> Result(a, b) {
  let panic_message =
    "Need to provide more than " <> times |> int.to_string <> " results"

  fn(count) {
    let result = results |> at(index: count)
    case result {
      Some(result) -> result
      None -> panic as panic_message
    }
  }
}
