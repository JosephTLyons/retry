import gleeunit/should
import internal/mock_types.{
  ConnectionTimeout, InvalidResponse, ServerUnavailable, ValidData,
}
import internal/test_utils.{fake_wait, result_returning_function}
import persevero.{RetryData}

// -------------------- Success

pub fn positive_4_custom_backoff_is_successful_test() {
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

  persevero.custom_backoff(wait_time: 100, next_wait_time: fn(previous) {
    { previous + 100 } * 2
  })
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
