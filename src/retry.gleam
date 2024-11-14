import gleam/bool
import gleam/erlang/process
import gleam/list
import gleam/set.{type Set}

/// Represents errors that can occur during a retry operation.
pub type RetryError(a) {
  /// Indicates that all retry attempts have been exhausted.
  /// Contains a list of all errors encountered during the execution attempts.
  RetriesExhausted(errors: List(a))

  /// Indicates that an error occurred which was not in the list of allowed
  /// errors. Contains the specific error that caused the retry to stop.
  UnallowedError(error: a)
}

/// Represents the error handling strategy for the retry operation.
pub type Allow(a) {
  /// Allows retrying for all types of errors.
  AllErrors

  /// Allows retrying only for the specified list of errors.
  Errors(errors: List(a))
}

fn to_set(allow allow: Allow(a)) -> Set(a) {
  case allow {
    Errors(errors) -> errors |> set.from_list
    AllErrors -> set.new()
  }
}

type RetryResult(a, b) =
  Result(a, RetryError(b))

@internal
pub type RetryData(a, b) {
  RetryData(result: RetryResult(a, b), wait_times: List(Int))
}

/// Retries an operation multiple times with a wait interval between attempts.
///
/// This function will attempt to execute the given operation up to n + 1 times,
/// where n is the specified number of retries. It will wait between each attempt
/// after the initial execution. The function will stop retrying if the operation
/// succeeds or if an unallowed error is encountered.
///
/// ## Parameters
///
/// - `times`: The number of retry attempts (n). The operation will be executed
///    n + 1 times in total.
/// - `wait_time_in_ms`: The time to wait between attempts, in milliseconds.
/// - `allow`: An `Allow` type specifying which errors are allowed and will
///    trigger a
///    retry. If `AllErrors`, a retry will be attempted for any type of error
///    encountered.
/// - `operation`: The operation to retry. It takes an index Int, where 0
///    corresponds to the initial attempt, and index 1 to n correspond to the
///    retry attempt count. The operation returns a Result.
///
/// ## Returns
///
/// Returns `Ok(a)` if the operation succeeds, or `Error(RetryError(b))` if all
/// attempts fail. The Error will be either `RetriesExhausted` containing a list
/// of all encountered errors, or `UnallowedError` containing the first
/// unallowed error encountered.
pub fn retry(
  times times: Int,
  wait_time_in_ms wait_time_in_ms: Int,
  allow allow: Allow(b),
  operation operation: fn() -> Result(a, b),
) -> RetryResult(a, b) {
  retry_with_wait(
    times: times,
    wait_time_in_ms: wait_time_in_ms,
    wait: wait,
    backoff_multiplier: 1,
    allow: allow,
    operation: fn(_) { operation() },
  ).result
}

/// Retries an operation multiple times with a wait interval between attempts.
///
/// This function behaves the same as `retry()`, with the following differences:
///
/// ## Parameters
///
/// - `backoff_multiplier`: A multiplier applied to the wait time after each
///    retry attempt. This creates an exponential backoff effect, increasing
///    the wait time between subsequent retries.
pub fn retry_with_backoff_multiplier(
  times times: Int,
  wait_time_in_ms wait_time_in_ms: Int,
  backoff_multiplier backoff_multiplier: Int,
  allow allow: Allow(b),
  operation operation: fn(Int) -> Result(a, b),
) -> RetryResult(a, b) {
  retry_with_wait(
    times: times,
    wait_time_in_ms: wait_time_in_ms,
    wait: wait,
    backoff_multiplier: backoff_multiplier,
    allow: allow,
    operation: operation,
  ).result
}

@internal
pub fn retry_with_wait(
  times times: Int,
  wait_time_in_ms wait_time_in_ms: Int,
  wait wait: fn(Int) -> Nil,
  backoff_multiplier backoff_multiplier: Int,
  allow allow: Allow(b),
  operation operation: fn(Int) -> Result(a, b),
) -> RetryData(a, b) {
  do_retry(
    times: times,
    remaining: times,
    wait_time_in_ms: wait_time_in_ms,
    wait: wait,
    backoff_multiplier: backoff_multiplier,
    allowed_errors: allow |> to_set,
    errors_acc: [],
    wait_time_acc: [],
    operation: operation,
  )
}

fn do_retry(
  times times: Int,
  remaining remaining: Int,
  wait_time_in_ms wait_time_in_ms: Int,
  wait wait: fn(Int) -> Nil,
  backoff_multiplier backoff_multiplier: Int,
  allowed_errors allowed_errors: Set(b),
  errors_acc errors_acc: List(b),
  wait_time_acc wait_time_acc: List(Int),
  operation operation: fn(Int) -> Result(a, b),
) -> RetryData(a, b) {
  use <- bool.guard(
    remaining < 0,
    RetryData(
      result: Error(RetriesExhausted(errors_acc |> list.reverse)),
      wait_times: wait_time_acc |> list.reverse,
    ),
  )

  let #(wait_time_acc, wait_time_in_ms) = case remaining < times {
    True -> {
      wait(wait_time_in_ms)
      #(
        [wait_time_in_ms, ..wait_time_acc],
        wait_time_in_ms * backoff_multiplier,
      )
    }
    False -> #(wait_time_acc, wait_time_in_ms)
  }

  case operation(times - remaining) {
    Ok(result) ->
      RetryData(result: Ok(result), wait_times: wait_time_acc |> list.reverse)
    Error(error) -> {
      let allow_error =
        set.is_empty(allowed_errors) || set.contains(allowed_errors, error)
      use <- bool.guard(
        !allow_error,
        RetryData(
          result: Error(UnallowedError(error)),
          wait_times: wait_time_acc |> list.reverse,
        ),
      )

      do_retry(
        times: times,
        remaining: remaining - 1,
        wait_time_in_ms: wait_time_in_ms,
        wait: wait,
        backoff_multiplier: backoff_multiplier,
        allowed_errors: allowed_errors,
        errors_acc: [error, ..errors_acc],
        wait_time_acc: wait_time_acc,
        operation: operation,
      )
    }
  }
}

fn wait(wait_time_in_ms: Int) -> Nil {
  let subject = process.new_subject()
  let _ = subject |> process.send_after(wait_time_in_ms, Nil)
  let _ = subject |> process.receive(within: wait_time_in_ms * 2)
  Nil
}
