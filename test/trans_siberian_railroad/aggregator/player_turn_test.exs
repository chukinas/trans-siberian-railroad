defmodule TransSiberianRailroad.Aggregator.PlayerTurnTest do
  use ExUnit.Case
  import TransSiberianRailroad.GameTestHelpers
  alias TransSiberianRailroad.Game
  alias TransSiberianRailroad.Messages

  describe "pass_rejected when" do
    test "not a player turn (e.g. setup)" do
      # ARRANGE
      game =
        Game.handle_commands([
          Messages.initialize_game(),
          add_player_commands(3),
          Messages.set_player_order([1, 2, 3])
        ])

      # ACT
      game = Game.handle_one_command(game, Messages.pass(1))

      # ASSERT
      assert event = fetch_single_event!(game.events, "pass_rejected")
      assert event.payload.passing_player == 1
    end

    test "not a player turn (e.g. end-of-turn sequence)"
    test "incorrect player"
  end
end
