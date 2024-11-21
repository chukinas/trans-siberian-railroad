defmodule TransSiberianRailroad.Interturn.PhaseShiftTest do
  # These tests are for the top-left corner of page 11 of the rulebook "IF THE GAME IS STILL IN PAHSE 1:"
  # Exception: the two bullets towards the bottom are handled by the Interturn.AuctionTest module

  use TransSiberianRailroad.Case, async: true
  @moduletag :start_game
  @moduletag :random_first_auction_phase

  describe "phase shift check occurs" do
    @describetag :simple_setup
    @describetag rig_auctions: [
                   %{company: "red", player: 1},
                   %{company: "blue"},
                   %{company: "green"},
                   %{company: "yellow"}
                 ]
    setup context do
      # GIVEN it's player 1's turn
      game = context.game
      # WHEN player 1 takes a turn
      game =
        [
          pass(1),
          pass(2),
          pass(3),
          pass(1)
        ]
        |> injest_commands(game)

      [game: game]
    end

    test ", but not if the interturn doesn't happen", context do
      # THEN we don't see a phase shift check because the
      # timing track has not advanced sufficiently
      refute find_command(context.game, "check_phase_shift")
    end

    test "during the interturn", context do
      # WHEN the 5th timing-track action occurs,
      game = pass(2) |> injest_commands(context.game)
      # THEN we finally see a phase shift check
      assert command = find_command(game, "check_phase_shift")
      assert command.payload == %{}
    end

    test "during the interturn, but not if we're already in phase 2"
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
