defmodule TransSiberianRailroad.Aggregator.GameEndSequenceTest do
  @moduledoc """
  command: `end_game` (emitted by `CheckForEndGame`)
  - cause
    - Dividends at end (dividend_track: …)
    - RR stock value at 75 (companies_at_max_stock_value: […])
    - Fewer than 2 public railroads (public railroads: […])

  game_end_sequence_started (emitted by GameEndSequence)
  - cause, same as above

  Game end Stock values determined
  Companies
  Company
  Stock value
  Note: “this takes nationalization into account but ignores the effect of private companies, the value of whose stock certificates is actually zero at game end”
  Emitted by StockValue after hearing “game end sequence begun”
  Game end Player score calculated (make sure private companies have no value). Emitted by StockCertificates after hearing “game end stock values determined”
  Player
  Score total
  Current money
  Stocks (list of maps)
  Company
  Count
  Value per
  Total value
  Company status: private or public
  Winner determined
  Winner
  Score
  Emitted by GameEndSequence after hearing a  “game end player score calculated”  for each player
  Tied winners determined
  Winners
  Score
  Emitted as alternative to above
  game ended
  Game id
  Emitted by GameEndSequence after hearing one of the above two
  """
  use ExUnit.Case, async: true
  import TransSiberianRailroad.GameHelpers
  import TransSiberianRailroad.GameTestHelpers
  alias TransSiberianRailroad.Constants
  alias TransSiberianRailroad.Messages

  taggable_setups()
  @moduletag :start_game
  @moduletag :random_first_auction_phase
  defp force_end_game(game, causes \\ [:nonsense]) do
    Messages.end_game(causes, user: :game) |> injest_commands(game)
  end

  describe "end_game (command)" do
    test "always results in game_end_sequence_started (event)", context do
      # GIVEN a game with a completed phase-1 auction,
      game = context.game
      # WHEN we force an end_game command,
      game = force_end_game(game)
      # THEN we should see a game_end_sequence_started event
      assert get_one_event(game, "game_end_sequence_started")
    end

    test "has one of three causes"

    test "has the same cause as the resulting game_end_sequence_started (event)", context do
      # GIVEN a game with a completed phase-1 auction,
      game = context.game
      # WHEN we force an end_game command,
      causes = [:stuff]
      game = force_end_game(game, causes)
      # THEN we should see a game_end_sequence_started event
      assert event = get_one_event(game, "game_end_sequence_started")
      assert event.payload.causes == causes
    end
  end

  describe "game_end_sequence_started" do
    test "always results in one game_end_stock_values_determined (event)", context do
      # GIVEN a game with a completed phase-1 auction,
      game = context.game
      # AND one of the companies has been nationalized
      nationalized_company = Constants.companies() |> Enum.take(4) |> Enum.random()
      game = handle_one_event(game, &Messages.company_nationalized(nationalized_company, &1))
      # WHEN we force an end_game command,
      game = force_end_game(game)
      # THEN we should see a game_end_sequence_started event
      assert event = get_one_event(game, "game_end_stock_values_determined")

      expected_company_stock_values =
        with company_stock_values =
               filter_events(game, "stock_value_set")
               |> Map.new(&{&1.payload.company, &1.payload.value}) do
          Enum.flat_map(Constants.companies(), fn company ->
            if (value = company_stock_values[company]) && company != nationalized_company do
              [%{company: company, stock_value: value}]
            else
              []
            end
          end)
        end

      assert event.payload == %{
               companies: expected_company_stock_values,
               note:
                 "this takes nationalization into account but ignores the effect of private companies, the value of whose stock certificates is actually zero at game end"
             }
    end

    test "operating private companies are worth nothing"
    test "operating public companies are worth something"
    test "nationalized companies are worth nothing"
    test "results in either winner_determined (event) or winners_determined (event)"

    test "results in game_ended (event)", context do
      # GIVEN a game with a completed phase-1 auction,
      game = context.game
      # WHEN we force an end_game command,
      game = force_end_game(game)
      # THEN we see a bunch of events ending with "game_ended"
      assert get_one_event(game, "game_ended")
    end
  end

  test "end game simple, happy path", context do
    # GIVEN a game with a completed phase-1 auction,
    game = context.game
    # AND one of the companies has been nationalized
    # WHEN we force an end_game command,
    game = force_end_game(game)
    # THEN we see a bunch of events ending with "game_ended"
    assert event = get_one_event(game, "game_end_player_money_calculated")
    assert length(event.payload.player_money) == context.player_count
    assert get_one_event(game, "game_end_player_stock_values_calculated")
    assert get_one_event(game, "player_scores_calculated")
    assert get_one_event(game, "winners_determined")
    assert get_one_event(game, "game_ended")
  end

  describe "game_end_stock_values_determined (event)" do
    test "does not include companies that have been nationalized"
  end
end
