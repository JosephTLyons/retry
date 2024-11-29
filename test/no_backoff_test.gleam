import bigben/clock
import gleeunit/should
import internal/mock_types.{
  ConnectionTimeout, InvalidResponse, ServerUnavailable,
}
import internal/utils.{fake_wait, result_returning_function}
import persevero.{MaxAttempts, RetryData, all_errors}

// -------------------- Failure

pub fn positive_3_no_backoff_fails_with_retries_exhausted_test() {
  let result_returning_function =
    result_returning_function(results: [
      // 1, wait 0
      Error(ConnectionTimeout),
      // 2, wait 0
      Error(ServerUnavailable),
      // 3, wait 0
      // error
      Error(InvalidResponse),
    ])

  let RetryData(result, wait_times, _) =
    persevero.no_backoff()
    |> persevero.execute_with_options(
      allow: all_errors,
      mode: MaxAttempts(3),
      operation: result_returning_function,
      wait_function: fake_wait,
      clock: clock.new(),
    )
  result
  |> should.equal(
    Error(
      persevero.RetriesExhausted([
        ConnectionTimeout,
        ServerUnavailable,
        InvalidResponse,
      ]),
    ),
  )
  wait_times |> should.equal([0, 0, 0])
}
