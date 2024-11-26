//// `persevero` executes a fallible operation multiple times.

import gleam/bool
import gleam/erlang/process
import gleam/int
import gleam/list
import gleam/yielder.{type Yielder}

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
  Config(yielder: Yielder(Int), max_attempts: Int, allow: fn(b) -> Bool)
}

/// Creates a new configuration with the specified `max_attempts`, `wait_time`,
/// and `backoff` function.
///
/// The `backoff` function determines how the wait time changes
/// between retry attempts. It takes the current wait time as input and
/// returns the next wait time.
///
/// Configuration defaults:
/// - `allow`: all errors
pub fn new(
  max_attempts max_attempts: Int,
  wait_time wait_time: Int,
  backoff backoff: fn(Int) -> Int,
) -> Config(a, b) {
  let yielder =
    yielder.unfold(wait_time, fn(acc) { yielder.Next(acc, backoff(acc)) })
  Config(yielder: yielder, max_attempts: max_attempts, allow: fn(_) { True })
}

/// Sets the logic for determining whether an error should trigger a retry.
/// Expects a function that takes an error and returns a boolean. Use this
/// function to match on your error types and return `True` for errors that
/// should trigger a retry, and `False` for errors that should not.
pub fn allow(
  config config: Config(a, b),
  allow allow: fn(b) -> Bool,
) -> Config(a, b) {
  Config(..config, allow: allow)
}

/// Sets a maximum time limit to wait between retries.
pub fn max_wait_time(
  config config: Config(a, b),
  max_wait_time max_wait_time: Int,
) -> Config(a, b) {
  let yielder = config.yielder |> yielder.map(int.min(_, max_wait_time))
  Config(..config, yielder: yielder)
}

/// Initiates the retry operation with the provided configuration and operation.
///
/// Returns `Ok(a)` if the operation succeeds, or `Error(RetryError(b))`.
pub fn execute(
  config config: Config(a, b),
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
  let yielder =
    yielder.from_list([0])
    |> yielder.append(config.yielder)
    |> yielder.take(config.max_attempts)
    |> yielder.map(int.max(_, 0))

  do_execute(
    config: config,
    yielder: yielder,
    wait_function: wait_function,
    errors_acc: [],
    wait_time_acc: [],
    operation: operation,
    attempt_number: 0,
  )
}

fn do_execute(
  config config: Config(a, b),
  yielder yielder: Yielder(Int),
  wait_function wait_function: fn(Int) -> Nil,
  errors_acc errors_acc: List(b),
  wait_time_acc wait_time_acc: List(Int),
  operation operation: fn(Int) -> Result(a, b),
  attempt_number attempt_number: Int,
) -> RetryData(a, b) {
  case yielder |> yielder.step() {
    yielder.Next(wait_time, yielder) -> {
      wait_function(wait_time)

      let wait_time_acc = [wait_time, ..wait_time_acc]

      case operation(attempt_number) {
        Ok(result) ->
          RetryData(
            result: Ok(result),
            wait_times: wait_time_acc |> list.reverse,
          )
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
            yielder: yielder,
            wait_function: wait_function,
            errors_acc: [error, ..errors_acc],
            wait_time_acc: wait_time_acc,
            operation: operation,
            attempt_number: attempt_number + 1,
          )
        }
      }
    }
    yielder.Done ->
      RetryData(
        result: Error(RetriesExhausted(errors_acc |> list.reverse)),
        wait_times: wait_time_acc |> list.reverse,
      )
  }
}

fn wait_function(wait_time wait_time: Int) -> Nil {
  let subject = process.new_subject()
  let _ = subject |> process.send_after(wait_time, Nil)
  let _ = subject |> process.receive(within: wait_time * 2)
  Nil
}
