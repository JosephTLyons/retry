//// `persevero` executes a fallible operation multiple times.

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

/// Creates a new retry configuration with the specified `wait_time` and
/// `backoff` function.
///
/// The `backoff` function determines how the wait time changes between retry
/// attempts. It takes the previous wait time as input and returns the next wait
/// time.
pub fn new(
  wait_time wait_time: Int,
  backoff backoff: fn(Int) -> Int,
) -> Yielder(Int) {
  yielder.unfold(0, fn(acc) {
    case acc {
      0 -> yielder.Next(0, wait_time)
      _ -> yielder.Next(acc, backoff(acc))
    }
  })
}

/// Sets a maximum number of retry attempts.
pub fn max_attempts(
  yielder yielder: Yielder(Int),
  max_attempts max_attempts: Int,
) -> Yielder(Int) {
  yielder |> yielder.take(max_attempts)
}

/// Sets a maximum time limit to wait between retries.
pub fn max_wait_time(
  yielder yielder: Yielder(Int),
  max_wait_time max_wait_time: Int,
) -> Yielder(Int) {
  yielder |> yielder.map(int.min(_, max_wait_time))
}

/// Initiates the retry operation with the operation.
///
/// `allow` sets the logic for determining whether an error should trigger a
/// retry. Expects a function that takes an error and returns a boolean. Use
/// this function to match on your error types and return `True` for errors that
/// should trigger a retry, and `False` for errors that should not. To allow all
/// errors, simply use `fn(_) { True }`.
///
/// Returns `Ok(a)` if the operation succeeds, or `Error(RetryError(b))`.
pub fn execute(
  yielder yielder: Yielder(Int),
  operation operation: fn() -> Result(a, b),
  allow allow: fn(b) -> Bool,
) -> RetryResult(a, b) {
  execute_with_wait(
    yielder: yielder,
    operation: fn(_) { operation() },
    allow: allow,
    wait_function: wait_function,
  ).result
}

@internal
pub fn execute_with_wait(
  yielder yielder: Yielder(Int),
  operation operation: fn(Int) -> Result(a, b),
  allow allow: fn(b) -> Bool,
  wait_function wait_function: fn(Int) -> Nil,
) -> RetryData(a, b) {
  let yielder = yielder |> yielder.map(int.max(_, 0))

  do_execute(
    yielder: yielder,
    operation: operation,
    allow: allow,
    wait_function: wait_function,
    wait_time_acc: [],
    errors_acc: [],
    attempt_number: 0,
  )
}

fn do_execute(
  yielder yielder: Yielder(Int),
  operation operation: fn(Int) -> Result(a, b),
  allow allow: fn(b) -> Bool,
  wait_function wait_function: fn(Int) -> Nil,
  wait_time_acc wait_time_acc: List(Int),
  errors_acc errors_acc: List(b),
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
          case allow(error) {
            True ->
              do_execute(
                yielder: yielder,
                operation: operation,
                allow: allow,
                wait_function: wait_function,
                wait_time_acc: wait_time_acc,
                errors_acc: [error, ..errors_acc],
                attempt_number: attempt_number + 1,
              )
            False ->
              RetryData(
                result: Error(UnallowedError(error)),
                wait_times: wait_time_acc |> list.reverse,
              )
          }
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
