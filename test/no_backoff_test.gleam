import gleeunit/should
import mock_types.{ConnectionTimeout, InvalidResponse, ServerUnavailable}
import persevero.{RetriesExhausted, RetryData}
import test_utils.{fake_wait, result_returning_function}

pub fn retry_exhausts_all_attempts_and_fails_with_no_backoff_test() {
  let times = 3
  let result_returning_function =
    result_returning_function(times: times, results: [
      // 1, wait 0
      Error(ConnectionTimeout),
      // 2, wait 0
      Error(ServerUnavailable),
      // 3, wait 0
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
