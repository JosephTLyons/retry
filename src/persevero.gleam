//// `persevero` executes a fallible operation multiple times.

import gleam/erlang/process
import gleam/function
import gleam/int
import gleam/list
import gleam/yielder.{type Yielder}

/// Represents errors that can occur during execution attempts.
pub type Error(a) {
  /// Indicates that all execution attempts have been exhausted. Contains an
  /// ordered list of all errors encountered during the execution attempts.
  RetriesExhausted(errors: List(a))

  /// Indicates that an error that wasn't allowed was encountered. Contains the
  /// specific error that caused execution to stop.
  UnallowedError(error: a)
}

type RetryResult(a, b) =
  Result(a, Error(b))

@internal
pub type RetryData(a, b) {
  RetryData(result: RetryResult(a, b), wait_times: List(Int))
}

/// Convenience function that you can supply to `execute`'s `allow` parameter to
/// allow all errors.
pub fn all_errors(_: a) -> Bool {
  True
}

/// Produces a custom wait stream.
pub fn custom_backoff(
  wait_time wait_time: Int,
  next_wait_time next_wait_time: fn(Int) -> Int,
) -> Yielder(Int) {
  yielder.iterate(wait_time, next_wait_time)
}

/// Produces a 0ms wait stream.
/// Ex: 0ms, 0ms, 0ms, ...
pub fn no_backoff() -> Yielder(Int) {
  yielder.repeat(0)
}

/// Produces a wait stream with a constant wait time.
/// Ex: 500ms, 500ms, 500ms, ...
pub fn constant_backoff(wait_time wait_time: Int) -> Yielder(Int) {
  yielder.iterate(wait_time, function.identity)
}

/// Produces a wait stream that increases linearly for each attempt.
/// Ex: 500ms, 1000ms, 1500ms, ...
pub fn linear_backoff(wait_time wait_time: Int, step step: Int) -> Yielder(Int) {
  yielder.iterate(wait_time, int.add(_, step))
}

/// Produces a wait stream that increases exponentially for each attempt.
/// time:
/// Ex: 500ms, 1000ms, 2000ms, 4000ms, ...
pub fn exponential_backoff(
  wait_time wait_time: Int,
  factor factor: Int,
) -> Yielder(Int) {
  yielder.iterate(wait_time, int.multiply(_, factor))
}

/// Adds a random integer between [1, `upper_bound`] to each wait time.
pub fn apply_jitter(
  wait_stream wait_stream: Yielder(Int),
  upper_bound upper_bound: Int,
) -> Yielder(Int) {
  apply_constant(
    wait_stream: wait_stream,
    adjustment: int.random(upper_bound) + 1,
  )
}

/// Adds a constant integer to each wait time.
pub fn apply_constant(
  wait_stream wait_stream: Yielder(Int),
  adjustment adjustment: Int,
) -> Yielder(Int) {
  wait_stream |> yielder.map(int.add(_, adjustment))
}

/// Multiplies each wait time by a constant factor.
pub fn apply_multiplier(
  wait_stream wait_stream: Yielder(Int),
  factor factor: Int,
) -> Yielder(Int) {
  wait_stream |> yielder.map(int.multiply(_, factor))
}

/// Caps each wait time at a maximum value.
pub fn apply_cap(
  wait_stream wait_stream: Yielder(Int),
  max_wait_time max_wait_time: Int,
) -> Yielder(Int) {
  wait_stream |> yielder.map(int.min(_, max_wait_time))
}

/// Initiates the execution process with the specified operation.
///
/// `allow` sets the logic for determining whether an error should trigger
/// another attempt. Expects a function that takes an error and returns a
/// boolean. Use this function to match on the encountered error and return
/// `True` for errors that should trigger another attempt, and `False` for
/// errors that should not. To allow all errors, use `all_errors`.
pub fn execute(
  wait_stream wait_stream: Yielder(Int),
  allow allow: fn(b) -> Bool,
  max_attempts max_attempts: Int,
  operation operation: fn() -> Result(a, b),
) -> RetryResult(a, b) {
  execute_with_wait(
    wait_stream: wait_stream,
    allow: allow,
    max_attempts: max_attempts,
    operation: fn(_) { operation() },
    wait_function: process.sleep,
  ).result
}

@internal
pub fn execute_with_wait(
  wait_stream wait_stream: Yielder(Int),
  allow allow: fn(b) -> Bool,
  max_attempts max_attempts: Int,
  operation operation: fn(Int) -> Result(a, b),
  wait_function wait_function: fn(Int) -> Nil,
) -> RetryData(a, b) {
  case max_attempts <= 0 {
    True -> RetryData(result: Error(RetriesExhausted([])), wait_times: [])
    False -> {
      let wait_stream =
        wait_stream
        |> yielder_prepend(0)
        |> yielder.take(max_attempts)
        |> yielder.map(int.max(_, 0))

      do_execute(
        wait_stream: wait_stream,
        allow: allow,
        max_attempts: max_attempts,
        operation: operation,
        wait_function: wait_function,
        wait_time_acc: [],
        errors_acc: [],
        attempt_number: 0,
      )
    }
  }
}

fn yielder_prepend(yielder: Yielder(a), element: a) -> Yielder(a) {
  use <- yielder.yield(element)
  yielder
}

fn do_execute(
  wait_stream wait_stream: Yielder(Int),
  allow allow: fn(b) -> Bool,
  max_attempts max_attempts: Int,
  operation operation: fn(Int) -> Result(a, b),
  wait_function wait_function: fn(Int) -> Nil,
  wait_time_acc wait_time_acc: List(Int),
  errors_acc errors_acc: List(b),
  attempt_number attempt_number: Int,
) -> RetryData(a, b) {
  case wait_stream |> yielder.step() {
    yielder.Next(wait_time, wait_stream) -> {
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
                wait_stream: wait_stream,
                allow: allow,
                max_attempts: max_attempts,
                operation: operation,
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
