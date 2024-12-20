defmodule Tsr.GameTest do
  use ExUnit.Case, async: true
  import Tsr.CommandFactory
  import Tsr.GameHelpers
  alias Tsr.Game

  test "game has some fields" do
    assert %{commands: [], events: [], aggregators: _} = Game.new()
  end

  test "smoke test" do
    # WHEN
    command = initialize_game()
    game = handle_commands([command])

    # THEN
    assert event = get_one_event(game, "game_initialized")
    assert %{game_id: _} = event.payload
  end

  test "event indexes start at 0"
  test "event indexes increment by 1"
end
