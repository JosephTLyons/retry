import gleam/option.{None, Some}
import gleeunit/should
import internal/list_extensions.{at}

pub fn at_test() {
  let items = ["a", "b", "c"]

  items
  |> at(-1)
  |> should.equal(None)

  items
  |> at(0)
  |> should.equal(Some("a"))

  items
  |> at(1)
  |> should.equal(Some("b"))

  items
  |> at(2)
  |> should.equal(Some("c"))

  items
  |> at(3)
  |> should.equal(None)
}
