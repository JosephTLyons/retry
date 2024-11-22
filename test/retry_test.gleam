import gleam/int
import gleam/option.{None, Some}
import gleeunit
import gleeunit/should
import list_extensions.{at}
import retry.{type RetryData, RetriesExhausted, RetryData, UnallowedError}

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

pub fn retry_with_negative_times_returns_retries_exhausted_error_test() {
  let times = -1
  let result_returning_function =
    result_returning_function(times: times, results: [
      Error(ConnectionTimeout),
      Error(ServerUnavailable),
      Error(InvalidResponse),
    ])

  retry.new()
  |> retry.max_attempts(times)
  |> retry.wait(100)
  |> retry.execute_with_wait(
    result_returning_function,
    wait_function: fake_wait,
  )
  |> should.equal(
    RetryData(result: Error(RetriesExhausted([])), wait_times: []),
  )
}

pub fn retry_fails_after_exhausting_attempts_test() {
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

  retry.new()
  |> retry.max_attempts(times)
  |> retry.wait(100)
  |> retry.execute_with_wait(
    result_returning_function,
    wait_function: fake_wait,
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

  retry.new()
  |> retry.max_attempts(times)
  |> retry.wait(100)
  |> retry.allow(fn(error) {
    case error {
      ConnectionTimeout | InvalidResponse -> True
      _ -> False
    }
  })
  |> retry.execute_with_wait(
    result_returning_function,
    wait_function: fake_wait,
  )
  |> should.equal(
    RetryData(result: Error(UnallowedError(ServerUnavailable)), wait_times: [
      0, 100,
    ]),
  )
}

pub fn retry_succeeds_on_allow_test() {
  let times = 3
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

  retry.new()
  |> retry.max_attempts(times)
  |> retry.wait(100)
  |> retry.allow(fn(error) {
    case error {
      ConnectionTimeout | ServerUnavailable -> True
      _ -> False
    }
  })
  |> retry.execute_with_wait(
    result_returning_function,
    wait_function: fake_wait,
  )
  |> should.equal(
    RetryData(result: Ok(SuccessfulConnection), wait_times: [0, 100, 100]),
  )
}

pub fn retry_succeeds_with_all_errors_test() {
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

  retry.new()
  |> retry.max_attempts(times)
  |> retry.wait(100)
  |> retry.allow(fn(_) { True })
  |> retry.execute_with_wait(
    result_returning_function,
    wait_function: fake_wait,
  )
  |> should.equal(
    RetryData(result: Ok(ValidData), wait_times: [0, 100, 100, 100]),
  )
}

// ------------ Backoff tests ------------

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

  retry.new()
  |> retry.max_attempts(times)
  |> retry.wait(100)
  |> retry.backoff(int.multiply(_, 2))
  |> retry.allow(fn(_) { True })
  |> retry.execute_with_wait(
    result_returning_function,
    wait_function: fake_wait,
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

  retry.new()
  |> retry.max_attempts(times)
  |> retry.wait(100)
  |> retry.backoff(int.add(_, 100))
  |> retry.allow(fn(_) { True })
  |> retry.execute_with_wait(
    result_returning_function,
    wait_function: fake_wait,
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

  retry.new()
  |> retry.max_attempts(times)
  |> retry.wait(100)
  |> retry.backoff(fn(wait) { wait |> int.add(100) |> int.multiply(2) })
  |> retry.allow(fn(_) { True })
  |> retry.execute_with_wait(
    result_returning_function,
    wait_function: fake_wait,
  )
  |> should.equal(
    RetryData(result: Ok(ValidData), wait_times: [0, 100, 400, 1000]),
  )
}

pub fn retry_with_multiplier_succeeds_after_allowed_errors_test() {
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

  retry.new()
  |> retry.max_attempts(times)
  |> retry.wait(100)
  |> retry.backoff(int.multiply(_, 3))
  |> retry.allow(fn(error) {
    case error {
      ConnectionTimeout | ServerUnavailable -> True
      _ -> False
    }
  })
  |> retry.execute_with_wait(
    result_returning_function,
    wait_function: fake_wait,
  )
  |> should.equal(
    RetryData(result: Ok(SuccessfulConnection), wait_times: [0, 100, 300]),
  )
}

pub fn retry_with_configuration_that_results_in_negative_wait_time_test() {
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

  retry.new()
  |> retry.max_attempts(times)
  |> retry.wait(-100)
  |> retry.backoff(int.subtract(_, 1000))
  |> retry.allow(fn(error) {
    case error {
      ConnectionTimeout | ServerUnavailable -> True
      _ -> False
    }
  })
  |> retry.execute_with_wait(
    result_returning_function,
    wait_function: fake_wait,
  )
  |> should.equal(
    RetryData(result: Ok(SuccessfulConnection), wait_times: [0, 0, 0]),
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
