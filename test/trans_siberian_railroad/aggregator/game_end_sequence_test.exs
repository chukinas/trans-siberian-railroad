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
  # import TransSiberianRailroad.CommandFactory
  # import TransSiberianRailroad.GameHelpers
  # import TransSiberianRailroad.GameTestHelpers
  # alias TransSiberianRailroad.Messages
  # alias TransSiberianRailroad.Metadata
  # alias TransSiberianRailroad.Players

  describe "end_game (command)" do
    test "always results in game_end_sequence_begun (event)"
    # TODO mv this to CheckForGameEndTest
    test "has one of three causes"
    test "has the same cause as the resulting game_end_sequence_begun (event)"
  end

  describe "game_end_sequence_begun (event)" do
    test "always results in one game_end_stock_values_determined (event)"
    test "results in one game_end_player_score_calculated (event) for each player"
    test "results in either winner_determined (event) or tied_winners_determined (event)"
    test "results in game_ended (event)"
  end

  describe "game_end_stock_values_determined (event)" do
    test "always has the same 'constant' note"
    test "has a :companies payload, a list of maps containing :company and :stock_value keys"
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
