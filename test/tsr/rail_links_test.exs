defmodule Tsr.RailLinksTest do
  use ExUnit.Case, async: true
  alias Tsr.RailLinks

  test "There are 13 external links" do
    external_locations =
      RailLinks.all()
      |> List.flatten()
      |> Enum.uniq()
      |> Enum.filter(&String.starts_with?(&1, "ext_"))

    assert 13 == length(external_locations)
  end
end
