defmodule TechTree.QueryHelpersTest do
  use ExUnit.Case, async: true

  alias TechTree.QueryHelpers

  test "parse_limit/2 uses the fallback for missing and invalid values" do
    assert QueryHelpers.parse_limit(%{}, 25) == 25
    assert QueryHelpers.parse_limit(%{"limit" => "not-a-number"}, 25) == 25
    assert QueryHelpers.parse_limit(%{"limit" => 0}, 25) == 25
    assert QueryHelpers.parse_limit(%{"limit" => "-4"}, 25) == 25
  end

  test "parse_limit/2 caps positive values at the shared ceiling" do
    assert QueryHelpers.parse_limit(%{"limit" => 10}, 25) == 10
    assert QueryHelpers.parse_limit(%{"limit" => "250"}, 25) == 200
  end

  test "parse_cursor/1 only accepts positive integers" do
    assert QueryHelpers.parse_cursor(%{}) == nil
    assert QueryHelpers.parse_cursor(%{"cursor" => 8}) == 8
    assert QueryHelpers.parse_cursor(%{"cursor" => "13"}) == 13
    assert QueryHelpers.parse_cursor(%{"cursor" => 0}) == nil
    assert QueryHelpers.parse_cursor(%{"cursor" => "-9"}) == nil
  end

  test "normalize_id/1 keeps integer ids and parses numeric strings" do
    assert QueryHelpers.normalize_id(42) == 42
    assert QueryHelpers.normalize_id("42") == 42
  end
end
