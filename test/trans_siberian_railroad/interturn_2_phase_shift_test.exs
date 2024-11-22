defmodule TransSiberianRailroad.Interturn.PhaseShiftTest do
  # These tests are for the top-left corner of page 11 of the rulebook "IF THE GAME IS STILL IN PAHSE 1:"
  # Exception: the two bullets towards the bottom are handled by the Interturn.AuctionTest module

  use TransSiberianRailroad.Case, async: true
  @moduletag :simple_setup
  @moduletag :start_game
  @moduletag :random_first_auction_phase
  @moduletag rig_auctions: [
               %{company: "red", player: 1, rubles: 48},
               %{company: "blue"},
               %{company: "green"},
               %{company: "yellow"}
             ]

  defp get_players(turn_number, amount) do
    index = turn_number - 1
    Stream.cycle(1..3) |> Enum.slice(index, amount)
  end

  defp pass(players, game) do
    Enum.map(players, &pass(&1)) |> injest_commands(game)
  end

  defp pass_on_company(players, company, game) do
    Enum.map(players, &pass_on_company(&1, company))
    |> injest_commands(game)
  end

  describe "phase shift check occurs" do
    test "during the interturn", context do
      # GIVEN the timing track has advanced 4 times
      game = context.game
      game = get_players(1, 4) |> pass(game)
      # AND therefore there's not yet been an interturn
      refute get_one_event(game, "interturn_started")
      refute find_command(game, "check_phase_shift")
      # WHEN the timing track advances one more time
      game = get_players(5, 1) |> pass(game)
      # THEN we finally see a phase shift check
      assert command = find_command(game, "check_phase_shift")
      assert command.payload == %{}
    end

    test "during the interturn, but not if we're already in phase 2", context do
      # GIVEN the phase shift has already occurred
      game = context.game
      game = get_players(1, 5) |> pass(game)
      assert [internal] = filter_events(game, "interturn_started")
      assert [check_phase_shift] = filter_commands(game, "check_phase_shift")
      game = get_players(6, 3) |> pass_on_company("black", game)
      game = get_players(9, 3) |> pass_on_company("white", game)
      # WHEN we have another interurn
      game = get_players(6, 5) |> pass(game)
      assert [_new_internal, ^internal] = filter_events(game, "interturn_started")
      # THEN there is not another phase shift check
      assert [^check_phase_shift] = filter_commands(game, "check_phase_shift")
    end
  end

  # SHIFT CRITERIA
  test "the phase shift does happen when all companies have stock values less than 48"
  test "the phase shift happens when a company has a stock value greater than or equal to 48"
  test "the check happens before the `stock adjustments` step"

  # IF SHIFT
  test "when a phase shift happens, we auction off black and white companies"
  test "that auction begins with the player who just had their turn"
  test "an initial rail link can be connected to ANY link built previously by any company"
  test "this initial rail link cannot be an external link"
  test "after a phase shift happens, we are in Phase 2"

  test "after the auction, it's the player's turn who is next in order (not the last auction winner)"

  test "initial rail links phase 1 must connect to moscow"
end
