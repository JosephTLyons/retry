import bigben/clock
import gleeunit/should
import internal/mock_types.{
  ConnectionTimeout, InvalidResponse, ServerUnavailable, ValidData,
}
import internal/utils.{fake_wait, result_returning_function}
import persevero.{MaxAttempts, RetryData, all_errors}

// -------------------- Success

pub fn positive_4_custom_backoff_is_successful_test() {
  let result_returning_function =
    result_returning_function(results: [
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

  let RetryData(result, wait_times, _) =
    persevero.custom_backoff(wait_time: 100, next_wait_time: fn(previous) {
      { previous + 100 } * 2
    })
    |> persevero.execute_with_options(
      allow: all_errors,
      mode: MaxAttempts(4),
      operation: result_returning_function,
      wait_function: fake_wait,
      clock: clock.new(),
    )
  result |> should.equal(Ok(ValidData))
  wait_times |> should.equal([0, 100, 400, 1000])
}
