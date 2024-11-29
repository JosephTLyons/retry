import bigben/fake_clock
import birl/duration
import gleam/option.{Some}
import internal/list_extensions

pub fn fake_wait(_: Int) -> Nil {
  Nil
}

pub fn advance_fake_clock(clock clock: fake_clock.FakeClock, by by: Int) -> Nil {
  let duration = duration.milli_seconds(by)
  clock |> fake_clock.advance(duration)
}

pub fn result_returning_function(
  results results: List(Result(a, b)),
) -> fn(Int) -> Result(a, b) {
  fn(count) {
    let assert Some(result) = results |> list_extensions.at(index: count)
    result
  }
}
