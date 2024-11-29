import gleam/option.{type Option, None, Some}

pub fn at(items items: List(a), index index: Int) -> Option(a) {
  do_at(items:, index:)
}

fn do_at(items items: List(a), index index: Int) -> Option(a) {
  case items, index {
    _, index if index < 0 -> None
    [_, ..rest], index if index > 0 -> do_at(items: rest, index: index - 1)
    [item, ..], _ -> Some(item)
    [], _ -> None
  }
}
