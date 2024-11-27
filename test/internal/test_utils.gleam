import gleam/int
import gleam/option.{None, Some}
import internal/list_extensions

pub fn fake_wait(_) -> Nil {
  Nil
}

pub fn result_returning_function(
  times times: Int,
  results results: List(Result(a, b)),
) -> fn(Int) -> Result(a, b) {
  let panic_message =
    "Need to provide more than " <> times |> int.to_string <> " results"

  fn(count) {
    let result = results |> list_extensions.at(index: count)
    case result {
      Some(result) -> result
      None -> panic as panic_message
    }
  }
}
