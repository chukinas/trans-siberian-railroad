defmodule TransSiberianRailroad.Interturn.AuctionTest do
  use TransSiberianRailroad.Case, async: true

  # These tests are for the top-left corner of page 11 of the rulebook "IF THE GAME IS STILL IN PAHSE 1:"
  # but only a subsection: the two bullet points towards the bottom.
  describe "When all players pass on a company," do
    test "the Nationalization Track advances 3 spaces"
    test "its stocks are no longer available for purchase"
  end
end
