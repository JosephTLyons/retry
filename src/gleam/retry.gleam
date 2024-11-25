//// `retry` executes a fallible operation multiple times. Various aspects can
//// be configured: the number of retry attempts, the duration between attempts,
//// the strategy for adjusting wait times, and the types of errors that should
//// trigger a retry.

import gleam/bool
import gleam/erlang/process
import gleam/function
import gleam/int
import gleam/list

/// Represents errors that can occur during a retry attempts.
pub type RetryError(a) {
  /// Indicates that all retry attempts have been exhausted. Contains an ordered
  /// list of all errors encountered during the execution attempts.
  RetriesExhausted(errors: List(a))

  /// Indicates that `retry` ran into an error that wasn't allowed. Contains the
  /// specific error that caused the retry to stop. By default, all errors are
  /// allowed. Use the `allow()` function to specify which errors should trigger
  /// a retry.
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
    wait_time: Int,
    next_wait_time: fn(Int) -> Int,
    allow: fn(b) -> Bool,
  )
}

/// Creates a new configuration with the specified `max_attempts` and
/// `wait_time`.
///
/// Configuration defaults:
/// - `next_wait_time`: constant
/// - `allow`: all errors
pub fn new(
  max_attempts max_attempts: Int,
  wait_time wait_time: Int,
) -> Config(a, b) {
  Config(
    max_attempts: max_attempts,
    wait_time: wait_time,
    next_wait_time: function.identity,
    allow: fn(_) { True },
  )
}

/// Sets the backoff strategy for increasing wait times between retry attempts.
/// Expects a function that takes the previous wait time and returns a the next
/// wait time.
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
/// Returns `Ok(a)` if the operation succeeds, or `Error(RetryError(b))`.
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

  let wait_time =
    case wait_time_acc {
      [] -> 0
      [0, ..] -> config.wait_time
      [wait_time, ..] -> wait_time |> config.next_wait_time
    }
    |> int.max(0)

  wait_function(wait_time)

  let wait_time_acc = [wait_time, ..wait_time_acc]

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

fn wait_function(wait_time wait_time: Int) -> Nil {
  let subject = process.new_subject()
  let _ = subject |> process.send_after(wait_time, Nil)
  let _ = subject |> process.receive(within: wait_time * 2)
  Nil
}
