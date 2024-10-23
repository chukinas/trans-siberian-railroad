defmodule TransSiberianRailroad.GameTest do
  use ExUnit.Case
  import TransSiberianRailroad.GameTestHelpers
  alias TransSiberianRailroad.Game
  alias TransSiberianRailroad.Messages

  test "game has some fields" do
    assert %{commands: [], events: [], aggregators: _} = Game.init()
  end

  test "smoke test" do
    # ACT
    command = Messages.initialize_game()
    game = Game.handle_commands([command])

    # ASSERT
    assert event = fetch_single_event!(game.events, "game_initialized")
    assert %{game_id: _} = event.payload
  end

  test "event indexes start at 0"
  test "event indexes increment by 1"
end
