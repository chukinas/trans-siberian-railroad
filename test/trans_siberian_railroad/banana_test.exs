defmodule TransSiberianRailroad.BananaTest do
  use ExUnit.Case
  alias TransSiberianRailroad.Game
  alias TransSiberianRailroad.Messages

  test "game has some fields" do
    assert %{commands: [], events: [], aggregators: _} = Game.init()
  end

  test "smoke test" do
    command = Messages.initialize_game()

    assert %{events: events} =
             Game.init()
             |> Game.handle_one_command(command)

    assert length(events) == 1
  end

  test "event indexes start at 0"
  test "event indexes increment by 1"
end
