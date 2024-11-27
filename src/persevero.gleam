//// `persevero` executes a fallible operation multiple times.

import gleam/erlang/process
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

/// Produces a delay stream with custom backoff logic.
pub fn custom_backoff(
  wait_time wait_time: Int,
  next_wait_time next_wait_time: fn(Int) -> Int,
) -> Yielder(Int) {
  yielder.unfold(wait_time, fn(acc) { yielder.Next(acc, next_wait_time(acc)) })
}

/// Produces a 0ms-delay stream: 0, 0, 0, ...
pub fn no_backoff() -> Yielder(Int) {
  custom_backoff(wait_time: 0, next_wait_time: fn(_) { 0 })
}

/// Produces a delay stream that waits for a constant amount of time: 500, 500,
/// 500, ...
pub fn constant_backoff(wait_time wait_time: Int) -> Yielder(Int) {
  custom_backoff(wait_time: wait_time, next_wait_time: fn(previous) {
    previous + 0
  })
}

/// Produces a delay stream that waits for a linearly-increasing amount of time:
/// 500, 1000, 1500, ...
pub fn linear_backoff(wait_time wait_time: Int, step step: Int) -> Yielder(Int) {
  custom_backoff(wait_time: wait_time, next_wait_time: fn(previous) {
    previous + step
  })
}

/// Produces a delay stream that waits for an exponentially-increasing amount of
/// time: 500, 1000, 2000, 4000, ...
pub fn exponential_backoff(
  wait_time wait_time: Int,
  factor factor: Int,
) -> Yielder(Int) {
  custom_backoff(wait_time: wait_time, next_wait_time: fn(previous) {
    previous * factor
  })
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
      let wait_stream = wait_stream |> yielder.take(max_attempts - 1)
      let wait_stream =
        yielder.from_list([0])
        |> yielder.append(wait_stream)
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
