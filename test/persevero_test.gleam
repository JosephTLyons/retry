import gleam/function
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

pub fn negative_retry_attempts_returns_retries_exhausted_error_test() {
  let times = -1
  let result_returning_function =
    result_returning_function(times: times, results: [
      Error(ConnectionTimeout),
      Error(ServerUnavailable),
      Error(InvalidResponse),
    ])

  persevero.new(times, 100, function.identity)
  |> persevero.execute_with_wait(
    wait_function: fake_wait,
    operation: result_returning_function,
  )
  |> should.equal(
    RetryData(result: Error(RetriesExhausted([])), wait_times: []),
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

  persevero.new(times, 100, function.identity)
  |> persevero.execute_with_wait(
    wait_function: fake_wait,
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

  persevero.new(times, 100, function.identity)
  |> persevero.allow(fn(error) {
    case error {
      ConnectionTimeout | InvalidResponse -> True
      _ -> False
    }
  })
  |> persevero.execute_with_wait(
    wait_function: fake_wait,
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

  persevero.new(times, 100, function.identity)
  |> persevero.allow(fn(error) {
    case error {
      ConnectionTimeout | ServerUnavailable -> True
      _ -> False
    }
  })
  |> persevero.execute_with_wait(
    wait_function: fake_wait,
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

  persevero.new(times, 100, function.identity)
  |> persevero.execute_with_wait(
    wait_function: fake_wait,
    operation: result_returning_function,
  )
  |> should.equal(
    RetryData(result: Ok(ValidData), wait_times: [0, 100, 100, 100]),
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

  persevero.new(times, 100, int.multiply(_, 2))
  |> persevero.execute_with_wait(
    wait_function: fake_wait,
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

  persevero.new(times, 100, int.add(_, 100))
  |> persevero.execute_with_wait(
    wait_function: fake_wait,
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

  persevero.new(times, 100, fn(wait) { wait |> int.add(100) |> int.multiply(2) })
  |> persevero.execute_with_wait(
    wait_function: fake_wait,
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

  persevero.new(times, 100, int.multiply(_, 3))
  |> persevero.allow(fn(error) {
    case error {
      ConnectionTimeout | ServerUnavailable -> True
      _ -> False
    }
  })
  |> persevero.execute_with_wait(
    wait_function: fake_wait,
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

  persevero.new(times, -100, int.subtract(_, 1000))
  |> persevero.execute_with_wait(
    wait_function: fake_wait,
    operation: result_returning_function,
  )
  |> should.equal(
    RetryData(result: Ok(SuccessfulConnection), wait_times: [0, 0, 0]),
  )
}

pub fn retry_with_max_wait_time_configuration_test() {
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

  persevero.new(times, 500, int.multiply(_, 2))
  |> persevero.allow(fn(error) {
    case error {
      ConnectionTimeout | ServerUnavailable -> True
      _ -> False
    }
  })
  |> persevero.max_wait_time(1000)
  |> persevero.execute_with_wait(
    wait_function: fake_wait,
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
