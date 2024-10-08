defmodule TransSiberianRailroad.BananaTest do
  use ExUnit.Case
  alias TransSiberianRailroad.Banana

  test "banana has some fields" do
    assert %{commands: [], events: [], aggregator_modules: _} = Banana.init()
  end
end
