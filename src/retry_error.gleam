/// Represents errors that can occur during a retry operation.
pub type RetryError(a) {
  /// Indicates that all retry attempts have been exhausted.
  /// Contains a list of all errors encountered during the retry attempts.
  AllAttemptsExhausted(errors: List(a))

  /// Indicates that an error occurred which was not in the list of allowed errors.
  /// Contains the specific error that caused the retry to stop.
  UnallowedError(error: a)
}
