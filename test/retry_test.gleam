import gleam/int
import gleam/option.{None, Some}
import gleeunit
import gleeunit/should
import list_extensions.{at}
import retry.{
  type RetryData, AllErrors, Errors, RetriesExhausted, RetryData, UnallowedError,
  retry_with_sleep,
}

pub fn main() {
  gleeunit.main()
}

type MockNetworkErrorResponse {
  ConnectionTimeout
  ServerUnavailable
  InvalidResponse
}

type MockNetworkSuccessResponse {
  SuccessfulConnection
  ValidData
}

const sleep_time_in_ms = 100

// TODO: Check all test cases and ensure they are correct
// TODO: Better test names

pub fn retry_with_negative_times_returns_error_test() {
  let times = -1
  let result_returning_function =
    result_returning_function(times: times, results: [
      Error(ConnectionTimeout),
      Error(ServerUnavailable),
      Error(InvalidResponse),
    ])

  retry_with_sleep(
    times: times,
    sleep_time_in_ms: sleep_time_in_ms,
    sleep: fake_sleep,
    backoff_multiplier: 1,
    allow: AllErrors,
    operation: result_returning_function,
  )
  |> should.equal(
    RetryData(result: Error(RetriesExhausted([])), sleep_times: []),
  )
}

pub fn retry_fails_after_exhausting_attempts_test() {
  let times = 2
  let result_returning_function =
    result_returning_function(times: times, results: [
      Error(ConnectionTimeout),
      // 0, sleep
      Error(ServerUnavailable),
      // 1, sleep
      Error(InvalidResponse),
      // 2, error
    ])

  retry_with_sleep(
    times: times,
    sleep_time_in_ms: sleep_time_in_ms,
    sleep: fake_sleep,
    backoff_multiplier: 1,
    allow: AllErrors,
    operation: result_returning_function,
  )
  |> should.equal(
    RetryData(
      result: Error(
        RetriesExhausted([ConnectionTimeout, ServerUnavailable, InvalidResponse]),
      ),
      sleep_times: [100, 100],
    ),
  )
}

pub fn retry_stops_on_non_allowed_error_test() {
  let times = 3
  let result_returning_function =
    result_returning_function(times: times, results: [
      Error(ConnectionTimeout),
      // 0, sleep
      Error(ServerUnavailable),
      // 1, error
      Error(InvalidResponse),
      Ok(SuccessfulConnection),
    ])

  retry_with_sleep(
    times: times,
    sleep_time_in_ms: sleep_time_in_ms,
    sleep: fake_sleep,
    backoff_multiplier: 1,
    allow: Errors([ConnectionTimeout, InvalidResponse]),
    operation: result_returning_function,
  )
  |> should.equal(
    RetryData(result: Error(UnallowedError(ServerUnavailable)), sleep_times: [
      100,
    ]),
  )
}

pub fn retry_succeeds_after_allowed_errors_test() {
  let times = 3
  let result_returning_function =
    result_returning_function(times: times, results: [
      Error(ConnectionTimeout),
      // 0, sleep
      Error(ServerUnavailable),
      // 1, sleep
      Ok(SuccessfulConnection),
      // 2, succeed
      Error(InvalidResponse),
    ])

  retry_with_sleep(
    times: times,
    sleep_time_in_ms: sleep_time_in_ms,
    sleep: fake_sleep,
    backoff_multiplier: 3,
    allow: Errors([ConnectionTimeout, ServerUnavailable]),
    operation: result_returning_function,
  )
  |> should.equal(
    RetryData(result: Ok(SuccessfulConnection), sleep_times: [100, 300]),
  )
}

pub fn retry_succeeds_on_allow_test() {
  let times = 3
  let result_returning_function =
    result_returning_function(times: times, results: [
      Error(ConnectionTimeout),
      // 0, sleep
      Error(ServerUnavailable),
      // 1, sleep
      Error(InvalidResponse),
      // 2, sleep
      Ok(SuccessfulConnection),
      // 3, succeed
    ])

  retry_with_sleep(
    times: times,
    sleep_time_in_ms: sleep_time_in_ms,
    sleep: fake_sleep,
    backoff_multiplier: 1,
    allow: Errors([ConnectionTimeout, ServerUnavailable, InvalidResponse]),
    operation: result_returning_function,
  )
  |> should.equal(
    RetryData(result: Ok(SuccessfulConnection), sleep_times: [100, 100, 100]),
  )
}

pub fn retry_succeeds_after_allow_test() {
  let times = 3
  let result_returning_function =
    result_returning_function(times: times, results: [
      Error(ConnectionTimeout),
      // 0, sleep
      Error(ServerUnavailable),
      // 1, sleep
      Error(InvalidResponse),
      // 2, sleep
      Ok(ValidData),
      // 3, succeed
    ])

  retry_with_sleep(
    times: times,
    sleep_time_in_ms: sleep_time_in_ms,
    sleep: fake_sleep,
    backoff_multiplier: 1,
    allow: AllErrors,
    operation: result_returning_function,
  )
  |> should.equal(
    RetryData(result: Ok(ValidData), sleep_times: [100, 100, 100]),
  )
}

pub fn retry_with_backoff_test() {
  let times = 3
  let result_returning_function =
    result_returning_function(times: times, results: [
      Error(ConnectionTimeout),
      // 0, sleep
      Error(ServerUnavailable),
      // 1, sleep
      Error(InvalidResponse),
      // 2, sleep
      Ok(ValidData),
      // 3, succeed
    ])

  retry_with_sleep(
    times: times,
    sleep_time_in_ms: sleep_time_in_ms,
    sleep: fake_sleep,
    backoff_multiplier: 2,
    allow: AllErrors,
    operation: result_returning_function,
  )
  |> should.equal(
    RetryData(result: Ok(ValidData), sleep_times: [100, 200, 400]),
  )
}

fn fake_sleep(_) {
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
