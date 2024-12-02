import bigben/clock
import bigben/fake_clock
import gleam/list
import gleeunit/should
import internal/mock_types.{
  ConnectionTimeout, InvalidResponse, ServerUnavailable, SuccessfulConnection,
  ValidData,
}
import internal/utils.{advance_fake_clock, fake_wait, result_returning_function}
import persevero.{
  Expiry, MaxAttempts, RetriesExhausted, RetryData, TimeExhausted,
  UnallowedError, all_errors,
}

// -------------------- Success

pub fn positive_4_constant_backoff_with_some_allowed_errors_is_successful_test() {
  let result_returning_function =
    result_returning_function(results: [
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

  let RetryData(result, wait_times, _) =
    persevero.constant_backoff(100)
    |> persevero.execute_with_options(
      allow: fn(error) {
        case error {
          ConnectionTimeout | ServerUnavailable -> True
          _ -> False
        }
      },
      mode: MaxAttempts(4),
      operation: result_returning_function,
      wait_function: fake_wait,
      clock: clock.new(),
    )
  result |> should.equal(Ok(SuccessfulConnection))
  wait_times |> should.equal([0, 100, 100])
}

pub fn positive_4_constant_backoff_with_all_allowed_errors_is_successful_test() {
  let result_returning_function =
    result_returning_function(results: [
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

  let RetryData(result, wait_times, _) =
    persevero.constant_backoff(100)
    |> persevero.execute_with_options(
      allow: all_errors,
      mode: MaxAttempts(4),
      operation: result_returning_function,
      wait_function: fake_wait,
      clock: clock.new(),
    )
  result |> should.equal(Ok(ValidData))
  wait_times |> should.equal([0, 100, 100, 100])
}

pub fn expiry_300_constant_backoff_with_all_allowed_errors_is_successful_test() {
  let expiry = 300
  let fake_clock = fake_clock.new()
  let constant_backoff_time = 100

  let result_returning_function =
    result_returning_function(results: [
      // 1, wait 0
      Error(ConnectionTimeout),
      // 2, wait 100 (100)
      Error(ServerUnavailable),
      // 3, wait 100 (200)
      Error(InvalidResponse),
      // 4, wait 100 (300)
      // succeed
      Ok(ValidData),
    ])

  let RetryData(result, wait_times, duration) =
    persevero.constant_backoff(constant_backoff_time)
    |> persevero.execute_with_options(
      allow: persevero.all_errors,
      mode: Expiry(expiry),
      operation: result_returning_function,
      wait_function: advance_fake_clock(fake_clock, _),
      clock: clock.from_fake(fake_clock),
    )

  wait_times |> should.equal([0, 100, 100, 100])
  duration |> should.equal(expiry)
  result |> should.equal(Ok(ValidData))
}

// -------------------- Failure

pub fn negative_1_times_fails_with_retries_exhausted_test() {
  let result_returning_function =
    result_returning_function(results: [
      Error(ConnectionTimeout),
      Error(ServerUnavailable),
      Error(InvalidResponse),
    ])

  let RetryData(result, wait_times, _) =
    persevero.constant_backoff(100)
    |> persevero.execute_with_options(
      allow: all_errors,
      mode: MaxAttempts(-1),
      operation: result_returning_function,
      wait_function: fake_wait,
      clock: clock.new(),
    )
  result |> should.equal(Error(RetriesExhausted([])))
  wait_times |> should.equal([])
}

pub fn positive_0_times_fails_with_retries_exhausted_test() {
  let result_returning_function =
    result_returning_function(results: [
      Error(ConnectionTimeout),
      Error(ServerUnavailable),
      Error(InvalidResponse),
    ])

  let RetryData(result, wait_times, _) =
    persevero.constant_backoff(100)
    |> persevero.execute_with_options(
      allow: all_errors,
      mode: MaxAttempts(0),
      operation: result_returning_function,
      wait_function: fake_wait,
      clock: clock.new(),
    )
  result |> should.equal(Error(RetriesExhausted([])))
  wait_times |> should.equal([])
}

pub fn positive_1_times_fails_with_retries_exhausted_test() {
  let result_returning_function =
    result_returning_function(results: [
      // 1, wait 0
      // error
      Error(ConnectionTimeout),
      Error(ServerUnavailable),
      Error(InvalidResponse),
    ])

  let RetryData(result, wait_times, _) =
    persevero.constant_backoff(100)
    |> persevero.execute_with_options(
      allow: all_errors,
      mode: MaxAttempts(1),
      operation: result_returning_function,
      wait_function: fake_wait,
      clock: clock.new(),
    )
  result |> should.equal(Error(RetriesExhausted([ConnectionTimeout])))
  wait_times |> should.equal([0])
}

pub fn positive_3_times_fails_with_retries_exhausted_test() {
  let result_returning_function =
    result_returning_function(results: [
      // 1, wait 0
      Error(ConnectionTimeout),
      // 2, wait 100
      Error(ServerUnavailable),
      // 3, wait 100
      // error
      Error(InvalidResponse),
    ])

  let RetryData(result, wait_times, _) =
    persevero.constant_backoff(100)
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
      RetriesExhausted([ConnectionTimeout, ServerUnavailable, InvalidResponse]),
    ),
  )
  wait_times |> should.equal([0, 100, 100])
}

pub fn positive_3_times_retry_fails_on_non_allowed_error_test() {
  let result_returning_function =
    result_returning_function(results: [
      // 1, wait 0
      Error(ConnectionTimeout),
      // 2, wait 100
      // error
      Error(ServerUnavailable),
      // Doesn't reach
      Error(InvalidResponse),
      Ok(SuccessfulConnection),
    ])

  let RetryData(result, wait_times, _) =
    persevero.constant_backoff(100)
    |> persevero.execute_with_options(
      allow: fn(error) {
        case error {
          ConnectionTimeout | InvalidResponse -> True
          _ -> False
        }
      },
      mode: MaxAttempts(3),
      operation: result_returning_function,
      wait_function: fake_wait,
      clock: clock.new(),
    )
  result |> should.equal(Error(UnallowedError(ServerUnavailable)))
  wait_times |> should.equal([0, 100])
}

// Same as comment below
pub fn expiry_negative_1_constant_backoff_with_all_allowed_errors_time_exhausted_test() {
  let expiry = -1
  let fake_clock = fake_clock.new()
  let constant_backoff_time = 100

  let RetryData(result, wait_times, duration) =
    persevero.constant_backoff(constant_backoff_time)
    |> persevero.execute_with_options(
      allow: persevero.all_errors,
      mode: Expiry(expiry),
      operation: fn(_) { Error(InvalidResponse) },
      wait_function: advance_fake_clock(fake_clock, _),
      clock: clock.from_fake(fake_clock),
    )

  wait_times |> should.equal([])
  duration |> should.equal(0)
  result |> should.equal(Error(TimeExhausted([])))
}

// I may want to revisit this. I'm not sure if expiry 0, or less than 0, should
// mean that one attempt is allowed. When set to MaxAttempts(0), we don't allow
// any attempts, but the first run is a 0 wait delay run, so maybe Expiry == 0
// should allow one attempt.
pub fn expiry_0_constant_backoff_with_all_allowed_errors_time_exhausted_test() {
  let expiry = 0
  let fake_clock = fake_clock.new()
  let constant_backoff_time = 100

  let RetryData(result, wait_times, duration) =
    persevero.constant_backoff(constant_backoff_time)
    |> persevero.execute_with_options(
      allow: persevero.all_errors,
      mode: Expiry(expiry),
      operation: fn(_) { Error(InvalidResponse) },
      wait_function: advance_fake_clock(fake_clock, _),
      clock: clock.from_fake(fake_clock),
    )

  wait_times |> should.equal([])
  duration |> should.equal(expiry)
  result |> should.equal(Error(TimeExhausted([])))
}

pub fn expiry_10000_constant_backoff_with_all_allowed_errors_time_exhausted_test() {
  let expiry = 10_000
  let fake_clock = fake_clock.new()
  let constant_backoff_time = 100
  let error = InvalidResponse

  let RetryData(result, wait_times, duration) =
    persevero.constant_backoff(constant_backoff_time)
    |> persevero.execute_with_options(
      allow: persevero.all_errors,
      mode: Expiry(expiry),
      operation: fn(_) { Error(InvalidResponse) },
      wait_function: advance_fake_clock(fake_clock, _),
      clock: clock.from_fake(fake_clock),
    )

  let attempts = expiry / constant_backoff_time
  let expected_wait_times = constant_backoff_time |> list.repeat(attempts)
  let expected_wait_times = [0, ..expected_wait_times]
  let expected_errors = error |> list.repeat(attempts + 1)

  wait_times |> should.equal(expected_wait_times)
  duration |> should.equal(expiry)
  result |> should.equal(Error(TimeExhausted(expected_errors)))
}

pub fn expiry_300_constant_backoff_with_all_allowed_errors_time_exhausted_test() {
  let expiry = 300
  let fake_clock = fake_clock.new()
  let constant_backoff_time = 100

  let result_returning_function =
    result_returning_function(results: [
      // 1, wait 0
      Error(ConnectionTimeout),
      // 2, wait 100 (100)
      Error(ServerUnavailable),
      // 3, wait 100 (200)
      Error(InvalidResponse),
      // 4, wait 100 (300)
      Error(ServerUnavailable),
      // error - time exhausted
      Ok(ValidData),
    ])

  let RetryData(result, wait_times, duration) =
    persevero.constant_backoff(constant_backoff_time)
    |> persevero.execute_with_options(
      allow: persevero.all_errors,
      mode: Expiry(expiry),
      operation: result_returning_function,
      wait_function: advance_fake_clock(fake_clock, _),
      clock: clock.from_fake(fake_clock),
    )

  wait_times |> should.equal([0, 100, 100, 100])
  duration |> should.equal(expiry)
  result
  |> should.equal(
    Error(
      TimeExhausted([
        ConnectionTimeout,
        ServerUnavailable,
        InvalidResponse,
        ServerUnavailable,
      ]),
    ),
  )
}
