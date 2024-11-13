defmodule TransSiberianRailroad.Aggregator.GameEndSequenceTest do
  @moduledoc """
  command: `end_game` (emitted by `CheckForEndGame`)
  - cause
    - Dividends at end (dividend_track: …)
    - RR stock value at 75 (companies_at_max_stock_value: […])
    - Fewer than 2 public railroads (public railroads: […])

  game_end_sequence_begun (emitted by GameEndSequence)
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
    test "always results in game_end_sequence_begun (event)", context do
      # GIVEN a game with a completed phase-1 auction,
      game = context.game

      # WHEN we force an end_game command,
      game = force_end_game(game)

      # THEN we should see a game_end_sequence_begun event
      assert get_one_event(game, "game_end_sequence_begun")
    end

    test "has one of three causes"

    test "has the same cause as the resulting game_end_sequence_begun (event)", context do
      # GIVEN a game with a completed phase-1 auction,
      game = context.game

      # WHEN we force an end_game command,
      causes = [:stuff]
      game = force_end_game(game, causes)

      # THEN we should see a game_end_sequence_begun event
      assert event = get_one_event(game, "game_end_sequence_begun")
      assert event.payload.causes == causes
    end
  end

  describe "game_end_sequence_begun (event)" do
    test "always results in one game_end_stock_values_determined (event)", context do
      # GIVEN a game with a completed phase-1 auction,
      game = context.game

      # AND one of the companies has been nationalized
      nationalized_company = Constants.companies() |> Enum.take(4) |> Enum.random()

      game = handle_one_event(game, &Messages.company_nationalized(nationalized_company, &1))

      # WHEN we force an end_game command,
      game = force_end_game(game)

      # THEN we should see a game_end_sequence_begun event
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

    test "results in one game_end_player_score_calculated (event) for each player"
    test "results in either winner_determined (event) or tied_winners_determined (event)"
    test "results in game_ended (event)"
  end

  describe "game_end_stock_values_determined (event)" do
    test "does not include companies that have been nationalized"
  end

  describe "game_end_player_score_calculated (event)" do
    test "get emitted for each player"

    test "has a :score_total payload (integer) equal to :current_money and :stocks[Access.all()].total_value"

    test "the stocks[company].total_value is the product of :count and :value_per"
    test "if :company_status is :private, the :value_per is 0"
  end

  describe "winner_determined (event)" do
    test "has a payload of :winner and :score"

    test "has a :score matching exactly ONE of the game_end_player_score_calculated (event) :score_total values"
  end

  describe "tied_winners_determined (event)" do
    test "has a payload of :winners and :score"

    test "has a :score matching that of the winners' game_end_player_score_calculated (event) :score_total values"
  end

  describe "game_ended (event)" do
    test "has a :game_id payload equal to that of game_initialized (event)"
  end
end
