defmodule TransSiberianRailroad.Aggregator.DividendsTest do
  use ExUnit.Case
  import TransSiberianRailroad.GameTestHelpers
  alias TransSiberianRailroad.Game
  alias TransSiberianRailroad.Messages
  alias TransSiberianRailroad.Players

  setup :start_game
  setup :rand_auction_phase

  test "awaiting_dividends after passing five times", context do
    # GIVEN we the first four player turns end in a "passed" action
    first_five_turns = Players.next_n_turns(context.player_order, context.start_player, 5)
    first_four_turns = Enum.take(first_five_turns, 4)

    commands =
      for player <- first_four_turns do
        Messages.pass(player)
      end

    game = Game.handle_commands(context.game, commands)
    refute get_latest_event_by_name(game.events, "awaiting_dividends")

    # WHEN the next player passes
    next_player = Enum.at(first_five_turns, -1)
    command = Messages.pass(next_player)
    game = Game.handle_one_command(game, command)

    # THEN the game will pay out dividends,
    # AND there will be one each of the awaiting_dividends, dividends_paid events
    assert event = fetch_single_event!(game.events, "awaiting_dividends")
    assert event.payload == %{}
  end
end
