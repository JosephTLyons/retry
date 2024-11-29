import bigben/clock
import gleeunit/should
import internal/mock_types.{
  ConnectionTimeout, InvalidResponse, ServerUnavailable, SuccessfulConnection,
  ValidData,
}
import internal/utils.{fake_wait, result_returning_function}
import persevero.{MaxAttempts, RetryData, all_errors}

// -------------------- Success

pub fn positive_4_linear_backoff_is_successful_test() {
  let result_returning_function =
    result_returning_function(results: [
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

  let RetryData(result, wait_times, _) =
    persevero.linear_backoff(100, 100)
    |> persevero.execute_with_options(
      allow: all_errors,
      mode: MaxAttempts(4),
      operation: result_returning_function,
      wait_function: fake_wait,
      clock: clock.new(),
    )
  result |> should.equal(Ok(ValidData))
  wait_times |> should.equal([0, 100, 200, 300])
}

pub fn positive_4_negative_wait_time_linear_backoff_is_successful_test() {
  let result_returning_function =
    result_returning_function(results: [
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

  let RetryData(result, wait_times, _) =
    persevero.linear_backoff(-100, -1000)
    |> persevero.execute_with_options(
      allow: all_errors,
      mode: MaxAttempts(4),
      operation: result_returning_function,
      wait_function: fake_wait,
      clock: clock.new(),
    )
  result |> should.equal(Ok(SuccessfulConnection))
  wait_times |> should.equal([0, 0, 0])
}
