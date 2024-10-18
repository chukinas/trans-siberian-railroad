defmodule TransSiberianRailroad.RailLinksTest do
  use ExUnit.Case
  alias TransSiberianRailroad.Locations
  alias TransSiberianRailroad.RailLink
  alias TransSiberianRailroad.RailLinks

  test "new/0 and Locations.new/0 return the same location ids" do
    expected_location_ids =
      Locations.new()
      |> Enum.map(& &1.id)
      |> Enum.sort()

    actual_location_ids =
      RailLinks.new()
      |> Enum.flat_map(& &1.linked_location_ids)
      |> Enum.uniq()
      |> Enum.sort()

    assert actual_location_ids == expected_location_ids
  end

  test "There are 13 external links" do
    assert 13 == RailLinks.new() |> Enum.filter(&RailLink.external_link?/1) |> Enum.count()
  end
end
