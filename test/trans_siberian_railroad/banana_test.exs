defmodule TransSiberianRailroad.BananaTest do
  use ExUnit.Case
  alias TransSiberianRailroad.Banana
  alias TransSiberianRailroad.Messages

  test "banana has some fields" do
    assert %{commands: [], events: [], aggregator_modules: _} = Banana.init()
  end

  test "smoke test" do
    command = Messages.initialize_game()

    assert %{events: events} =
             Banana.init()
             |> Banana.handle_command(command)

    assert length(events) == 1
  end

  test "event indexes start at 0"
  test "event indexes increment by 1"
end
