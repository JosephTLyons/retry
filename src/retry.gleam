import gleam/bool
import gleam/erlang/process
import gleam/list
import gleam/set.{type Set}

/// Represents errors that can occur during a retry operation.
pub type RetryError(a) {
  /// Indicates that all retry attempts have been exhausted.
  /// Contains a list of all errors encountered during the execution attempts.
  RetriesExhausted(errors: List(a))

  /// Indicates that an error occurred which was not in the list of allowed errors.
  /// Contains the specific error that caused the retry to stop.
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
  RetryData(result: RetryResult(a, b), sleep_times: List(Int))
}

// TODO: Update documentation

/// Retries an operation multiple times with a sleep interval between attempts.
///
/// This function will attempt to execute the given operation up to n + 1 times,
/// where n is the specified number of retries. It will sleep between each attempt
/// after the initial execution. The function will stop retrying if the operation
/// succeeds or if an unallowed error is encountered.
///
/// ## Parameters
///
/// - `times`: The number of retry attempts (n). The operation will be executed
///    n + 1 times in total.
/// - `sleep_time_in_ms`: The time to sleep between attempts, in milliseconds.
/// - `allow`: A list of errors that are allowed and will trigger a
///    retry. If empty, a retry will be attempted for any type of error
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
  sleep_time_in_ms sleep_time_in_ms: Int,
  allow allow: Allow(b),
  operation operation: fn(Int) -> Result(a, b),
) -> RetryResult(a, b) {
  retry_with_sleep(
    times: times,
    sleep_time_in_ms: sleep_time_in_ms,
    sleep: sleep,
    backoff_multiplier: 1,
    allow: allow,
    operation: operation,
  ).result
}

pub fn retry_with_backoff_multiplier(
  times times: Int,
  sleep_time_in_ms sleep_time_in_ms: Int,
  backoff_multiplier backoff_multiplier: Int,
  allow allow: Allow(b),
  operation operation: fn(Int) -> Result(a, b),
) -> RetryResult(a, b) {
  retry_with_sleep(
    times: times,
    sleep_time_in_ms: sleep_time_in_ms,
    sleep: sleep,
    backoff_multiplier: backoff_multiplier,
    allow: allow,
    operation: operation,
  ).result
}

@internal
pub fn retry_with_sleep(
  times times: Int,
  sleep_time_in_ms sleep_time_in_ms: Int,
  sleep sleep: fn(Int) -> Nil,
  backoff_multiplier backoff_multiplier: Int,
  allow allow: Allow(b),
  operation operation: fn(Int) -> Result(a, b),
) -> RetryData(a, b) {
  do_retry(
    times: times,
    remaining: times,
    sleep_time_in_ms: sleep_time_in_ms,
    sleep: sleep,
    backoff_multiplier: backoff_multiplier,
    allowed_errors: allow |> to_set,
    errors_acc: [],
    sleep_time_acc: [],
    operation: operation,
  )
}

// TODO: Clean up logic, has to be a better way
fn do_retry(
  times times: Int,
  remaining remaining: Int,
  sleep_time_in_ms sleep_time_in_ms: Int,
  sleep sleep: fn(Int) -> Nil,
  backoff_multiplier backoff_multiplier: Int,
  allowed_errors allowed_errors: Set(b),
  errors_acc errors_acc: List(b),
  sleep_time_acc sleep_time_acc: List(Int),
  operation operation: fn(Int) -> Result(a, b),
) -> RetryData(a, b) {
  use <- bool.guard(
    remaining < 0,
    RetryData(
      result: Error(RetriesExhausted(errors_acc |> list.reverse)),
      sleep_times: sleep_time_acc |> list.reverse,
    ),
  )

  let #(sleep_time_acc, sleep_time_in_ms) = case remaining < times {
    True -> {
      sleep(sleep_time_in_ms)
      #(
        [sleep_time_in_ms, ..sleep_time_acc],
        sleep_time_in_ms * backoff_multiplier,
      )
    }
    False -> #(sleep_time_acc, sleep_time_in_ms)
  }

  case operation(times - remaining) {
    Ok(result) ->
      RetryData(result: Ok(result), sleep_times: sleep_time_acc |> list.reverse)

    Error(error) -> {
      let allow_error =
        set.is_empty(allowed_errors) || set.contains(allowed_errors, error)
      use <- bool.guard(
        !allow_error,
        RetryData(
          result: Error(UnallowedError(error)),
          sleep_times: sleep_time_acc |> list.reverse,
        ),
      )

      do_retry(
        times: times,
        remaining: remaining - 1,
        sleep_time_in_ms: sleep_time_in_ms,
        sleep: sleep,
        backoff_multiplier: backoff_multiplier,
        allowed_errors: allowed_errors,
        errors_acc: [error, ..errors_acc],
        sleep_time_acc: sleep_time_acc,
        operation: operation,
      )
    }
  }
}

fn sleep(sleep_time_in_ms: Int) {
  process.sleep(sleep_time_in_ms)
}
// TODO: Research if we can omit the Int in the callback
