//// `retry` provides a flexible mechanism for executing an operation n times
//// after an initial failure. Various aspects can be configured: the number of
//// retry attempts, the duration between attempts, the strategy for adjusting
//// wait times, and the types of errors that should trigger a retry.

import gleam/bool
import gleam/erlang/process
import gleam/function
import gleam/int
import gleam/list

/// Represents errors that can occur during a retry operation.
pub type RetryError(a) {
  /// Indicates that all retry attempts have been exhausted.
  /// Contains a list of all errors encountered during the execution attempts.
  RetriesExhausted(errors: List(a))

  /// Indicates that an error occurred which was not in the list of allowed
  /// errors. Contains the specific error that caused the retry to stop.
  UnallowedError(error: a)
}

type RetryResult(a, b) =
  Result(a, RetryError(b))

@internal
pub type RetryData(a, b) {
  RetryData(result: RetryResult(a, b), wait_times: List(Int))
}

pub opaque type Config(a, b) {
  Config(
    max_attempts: Int,
    duration: Int,
    next_wait_time: fn(Int) -> Int,
    allow: fn(b) -> Bool,
  )
}

pub type NetworkError {
  ServerDown
  Timeout(Int)
  InvalidStatusCode(Int)
  InvalidResponseBody(String)
}

// TODO: Function ordering here
// Fuzzying: https://discord.com/channels/768594524158427167/768594524158427170/1309557318731698216
// TODO: Double check documentation

/// Creates a new configuration with default values.
/// Default values are:
/// - `max_attempts`: 3
/// - `duration`: 500 (ms)
/// - `next_wait_time`: constant
/// - `allow`: all errors
pub fn new() -> Config(a, b) {
  Config(
    max_attempts: 3,
    duration: 500,
    next_wait_time: function.identity,
    allow: fn(_) { True },
  )
}

/// Sets the number of times to attempt the operation.
pub fn max_attempts(
  config: Config(a, b),
  max_attempts max_attempts: Int,
) -> Config(a, b) {
  Config(..config, max_attempts: max_attempts)
}

/// Sets the time to wait (in ms) between retry attempts.
pub fn wait(config: Config(a, b), duration duration: Int) -> Config(a, b) {
  Config(..config, duration: duration)
}

/// Sets the backoff strategy for increasing wait times between retry attempts.
/// Expects a function that takes the previous wait time and returns a new wait
/// time.
pub fn backoff(
  config: Config(a, b),
  next_wait_time next_wait_time: fn(Int) -> Int,
) -> Config(a, b) {
  Config(..config, next_wait_time: next_wait_time)
}

/// Sets the logic for determining whether an error should trigger a retry.
/// Expects a function that takes an error and returns a boolean. Use this
/// function to match on your error types and return `True` for errors that
/// should trigger a retry, and `False` for errors that should not.
pub fn allow(config: Config(a, b), allow allow: fn(b) -> Bool) -> Config(a, b) {
  Config(..config, allow: allow)
}

/// Initiates the retry operation with the provided configuration and operation.
///
/// Returns `Ok(a)` if the operation succeeds, or `Error(RetryError(b))` if all
/// attempts fail. The Error will be either `RetriesExhausted` containing a list
/// of all encountered errors, or `UnallowedError` containing the first
/// unallowed error encountered.
pub fn execute(
  config: Config(a, b),
  operation operation: fn() -> Result(a, b),
) -> RetryResult(a, b) {
  execute_with_wait(
    config: config,
    wait_function: wait_function,
    operation: fn(_) { operation() },
  ).result
}

@internal
pub fn execute_with_wait(
  config config: Config(a, b),
  wait_function wait_function: fn(Int) -> Nil,
  operation operation: fn(Int) -> Result(a, b),
) -> RetryData(a, b) {
  do_execute(
    config: config,
    wait_function: wait_function,
    errors_acc: [],
    wait_time_acc: [],
    operation: operation,
    attempt_number: 0,
  )
}

fn do_execute(
  config config: Config(a, b),
  wait_function wait_function: fn(Int) -> Nil,
  errors_acc errors_acc: List(b),
  wait_time_acc wait_time_acc: List(Int),
  operation operation: fn(Int) -> Result(a, b),
  attempt_number attempt_number: Int,
) -> RetryData(a, b) {
  use <- bool.guard(
    attempt_number >= config.max_attempts,
    RetryData(
      result: Error(RetriesExhausted(errors_acc |> list.reverse)),
      wait_times: wait_time_acc |> list.reverse,
    ),
  )

  // Clean this logic up - feels #yucky
  let duration = case attempt_number == 0 {
    True -> 0
    False -> {
      case wait_time_acc |> list.first {
        Ok(0) | Error(_) -> config.duration
        Ok(duration) -> duration |> config.next_wait_time
      }
      |> int.max(0)
    }
  }

  wait_function(duration)

  let wait_time_acc = [duration, ..wait_time_acc]

  case operation(attempt_number) {
    Ok(result) ->
      RetryData(result: Ok(result), wait_times: wait_time_acc |> list.reverse)
    Error(error) -> {
      use <- bool.guard(
        !config.allow(error),
        RetryData(
          result: Error(UnallowedError(error)),
          wait_times: wait_time_acc |> list.reverse,
        ),
      )

      do_execute(
        config: config,
        wait_function: wait_function,
        errors_acc: [error, ..errors_acc],
        wait_time_acc: wait_time_acc,
        operation: operation,
        attempt_number: attempt_number + 1,
      )
    }
  }
}

fn wait_function(duration duration: Int) -> Nil {
  let subject = process.new_subject()
  let _ = subject |> process.send_after(duration, Nil)
  let _ = subject |> process.receive(within: duration * 2)
  Nil
}
