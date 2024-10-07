defmodule TransSiberianRailroad.AuctionTest do
  use ExUnit.Case
  import TransSiberianRailroad.GameTestHelpers
  alias TransSiberianRailroad.Auction
  alias TransSiberianRailroad.Event
  alias TransSiberianRailroad.Messages

  describe "first auction" do
    setup do
      player_count = Enum.random(3..5)

      start_game_commands =
        List.flatten([
          Messages.initialize_game(),
          add_player_commands(player_count),
          Messages.start_game(Enum.random(1..player_count))
        ])

      [started_game: game_from_commands(start_game_commands)]
    end

    test "A started game also has an auction_started event", %{started_game: game} do
      assert game_has_event?(game, "game_started")

      case Enum.filter(game.events, &(&1.name == "auction_started")) do
        [%Event{payload: payload}] ->
          assert Auction.current_bidder!(game.auction) == payload.current_bidder
      end

      assert Auction.in_progress?(game.auction)
    end
  end
end
