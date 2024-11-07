defmodule TransSiberianRailroad.Aggregator.StockValueTest do
  use ExUnit.Case, async: true
  import TransSiberianRailroad.CommandFactory
  import TransSiberianRailroad.GameHelpers
  import TransSiberianRailroad.GameTestHelpers
  alias TransSiberianRailroad.Players

  setup :start_game
  setup :rand_auction_phase

  test "dividends_paid after passing five times", context do
    # GIVEN we the first four player turns end in a "passed" action
    first_five_turns = Players.next_n_turns(context.player_order, context.start_player, 5)
    first_four_turns = Enum.take(first_five_turns, 4)

    commands =
      for player <- first_four_turns do
        pass(player)
      end

    game = handle_commands(context.game, commands)
    refute get_latest_event(game, "dividends_paid")

    # WHEN the next player passes
    next_player = Enum.at(first_five_turns, -1)
    command = pass(next_player)
    game = handle_one_command(game, command)

    assert find_command(game, "pay_company_dividends")

    # THEN the game will pay out dividends,
    # AND there will be one each of the awaiting_dividends, dividends_paid events
    assert event = fetch_single_event!(game, "dividends_paid")
    assert event.payload == %{}
  end

  test "the certificate value is always rounded up (and make sure we test various stock counts too)"
  test "money actually gets transferred"
end
