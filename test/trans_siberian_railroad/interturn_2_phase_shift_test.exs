defmodule TransSiberianRailroad.Interturn.PhaseShiftTest do
  # These tests are for the top-left corner of page 11 of the rulebook "IF THE GAME IS STILL IN PAHSE 1:"
  # Exception: the two bullets towards the bottom are handled by the Interturn.AuctionTest module

  use TransSiberianRailroad.Case, async: true
  # CHECK
  test "the phase shift check does not happen if the interturn doesn't happen"
  test "the phase shift check happens during the interturn, but not if we're already in phase 2"
  test "the phase shift check happens during the interturn, and only if we're in phase 1"

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
