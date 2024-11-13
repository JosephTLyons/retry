import gleam/bool
import gleam/erlang/process
import gleam/result
import gleam/set.{type Set}

/// Represents errors that can occur during a retry operation.
pub type RetryError(a) {
  /// Indicates that all retry attempts have been exhausted.
  /// Contains a list of all errors encountered during the retry attempts.
  AllAttemptsExhausted(errors: List(a))

  /// Indicates that an error occurred which was not in the list of allowed errors.
  /// Contains the specific error that caused the retry to stop.
  UnallowedError(error: a)
}

/// Retries an operation multiple times with a sleep interval between attempts.
///
/// This function will attempt to execute the given operation up to the specified
/// number of times, sleeping between each attempt. It will stop retrying if the
/// operation succeeds or if an unallowed error is encountered.
///
/// ## Parameters
///
/// - `times`: The maximum number of times to attempt the operation.
/// - `sleep_time_in_ms`: The time to sleep between attempts, in milliseconds.
/// - `allowed_errors`: A list of errors that are allowed and will trigger a retry.
///   If empty, retry will be attempted for all errors encountered.
/// - `operation`: The operation to retry. It takes an Int (the current execution number,
///   zero-indexed) and returns a Result.
///
/// ## Returns
///
/// Returns `Ok(a)` if the operation succeeds, or `Error(RetryError(b))` if all
/// attempts fail. The Error will be either `AllAttemptsExhausted` containing a list
/// of all encountered errors, or `UnallowedError` containing the unallowed error.
pub fn retry(
  times times: Int,
  sleep_time_in_ms sleep_time_in_ms: Int,
  allowed_errors allowed_errors: List(b),
  operation operation: fn(Int) -> Result(a, b),
) -> Result(a, RetryError(b)) {
  retry_with_sleep(
    times: times,
    sleep_time_in_ms: sleep_time_in_ms,
    sleep: sleep,
    allowed_errors: allowed_errors,
    operation: operation,
  )
}

@internal
pub fn retry_with_sleep(
  times times: Int,
  sleep_time_in_ms sleep_time_in_ms: Int,
  sleep sleep: fn(Int) -> Nil,
  allowed_errors allowed_errors: List(b),
  operation operation: fn(Int) -> Result(a, b),
) -> Result(a, RetryError(b)) {
  do_retry(
    times: times,
    remaining: times,
    sleep_time_in_ms: sleep_time_in_ms,
    sleep: sleep,
    allowed_errors: allowed_errors |> set.from_list,
    errors_acc: [],
    operation: operation,
  )
}

fn do_retry(
  times times: Int,
  remaining remaining: Int,
  sleep_time_in_ms sleep_time_in_ms: Int,
  sleep sleep: fn(Int) -> Nil,
  allowed_errors allowed_errors: Set(b),
  errors_acc errors_acc: List(b),
  operation operation: fn(Int) -> Result(a, b),
) -> Result(a, RetryError(b)) {
  use <- bool.guard(remaining < 0, Error(AllAttemptsExhausted(errors_acc)))
  use error <- result.try_recover(operation(times - remaining))

  let allow_error =
    set.is_empty(allowed_errors) || set.contains(allowed_errors, error)
  use <- bool.guard(!allow_error, Error(UnallowedError(error)))

  sleep(sleep_time_in_ms)

  do_retry(
    times: times,
    remaining: remaining - 1,
    sleep_time_in_ms: sleep_time_in_ms,
    sleep: sleep,
    allowed_errors: allowed_errors,
    errors_acc: [error, ..errors_acc],
    operation: operation,
  )
}

fn sleep(sleep_time_in_ms: Int) {
  process.sleep(sleep_time_in_ms)
}
