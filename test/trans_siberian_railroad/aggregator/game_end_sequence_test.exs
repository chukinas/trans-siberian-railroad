defmodule TransSiberianRailroad.Aggregator.GameEndSequenceTest do
  use TransSiberianRailroad.Case, async: true

  @moduletag :start_game
  @moduletag :random_first_auction_phase

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
