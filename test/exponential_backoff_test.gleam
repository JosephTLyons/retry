import gleeunit/should
import mock_types.{
  ConnectionTimeout, InvalidResponse, ServerUnavailable, SuccessfulConnection,
  ValidData,
}
import persevero.{RetryData}
import test_utils.{fake_wait, result_returning_function}

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
      // 2, wait 53
      Error(ServerUnavailable),
      // 3, wait 103
      // succeed
      Ok(SuccessfulConnection),
      // Doesn't reach
      Error(InvalidResponse),
    ])

  persevero.exponential_backoff(50, 3)
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
      // 2, wait 53
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
