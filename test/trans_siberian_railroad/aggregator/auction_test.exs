defmodule TransSiberianRailroad.Aggregator.AuctionTest do
  use ExUnit.Case
  import TransSiberianRailroad.GameTestHelpers
  alias TransSiberianRailroad.Aggregator.Auction
  alias TransSiberianRailroad.Aggregator.Players
  alias TransSiberianRailroad.Event
  alias TransSiberianRailroad.Messages

  test "A started game also has an auction_started event" do
    game = start_game_commands() |> game_from_commands()
    assert game_has_event?(game, "game_started")

    case Enum.filter(game.events, &(&1.name == "auction_started")) do
      [%Event{payload: payload}] ->
        current_bidder = Auction.get_current_bidder(game.auction)
        assert current_bidder
        assert current_bidder == payload.current_bidder
    end

    assert Auction.in_progress?(game.auction)
  end

  test "If all players pass on a railroad, a 'company_removed' event is generated" do
    # ARRANGE
    game = start_game_commands() |> game_from_commands()
    player_count = player_count(game.events)

    # ACT
    {auction, _new_events} = Auction.state(game.events)
    assert current_player = Auction.get_current_bidder(auction)

    pass_commands =
      player_order(game.events)
      |> Players.player_order_once_around_the_table(current_player)
      |> Enum.map(&Messages.pass_on_company(&1, :red))

    game = handle_commands(game, pass_commands)

    # ASSERT
    assert length(filter_events_by_name(game.events, "company_passed")) == player_count

    assert %{company_id: :red} =
             fetch_single_event_payload!(game.events, "company_removed_from_game")

    assert 0 == get_active_companies(game.events)
  end
end
