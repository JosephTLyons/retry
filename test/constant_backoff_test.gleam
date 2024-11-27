import gleeunit/should
import mock_types.{
  ConnectionTimeout, InvalidResponse, ServerUnavailable, SuccessfulConnection,
  ValidData,
}
import persevero.{RetriesExhausted, RetryData, UnallowedError}
import test_utils.{fake_wait, result_returning_function}

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
      // 1, wait 0
      // error
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
