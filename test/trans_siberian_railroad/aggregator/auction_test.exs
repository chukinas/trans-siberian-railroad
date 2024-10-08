defmodule TransSiberianRailroad.Aggregator.AuctionTest do
  use ExUnit.Case
  import TransSiberianRailroad.GameTestHelpers
  alias TransSiberianRailroad.Aggregator.Auction
  alias TransSiberianRailroad.Aggregator.Players
  alias TransSiberianRailroad.Banana
  alias TransSiberianRailroad.Messages

  test "game_started -> auction_phase_started" do
    # ARRANGE
    commands = start_game_commands()

    # ACT
    game = Banana.handle_commands(commands)
    assert game_has_event?(game, "game_started")

    # ASSERT
    assert fetch_single_event!(game.events, "auction_phase_started")
  end

  test "auction_phase_started -> company_auction_started" do
    # ARRANGE
    commands = start_game_commands()

    # ACT
    game = Banana.handle_commands(commands)
    assert fetch_single_event!(game.events, "auction_phase_started")

    # ASSERT
    assert %{company: :red} = fetch_single_event!(game.events, "company_auction_started").payload
  end

  test "company_not_opened event when all players pass on a company auction" do
    # ARRANGE
    player_count = Enum.random(3..5)
    game = start_game_commands(player_count) |> Banana.handle_commands()

    # ACT
    auction = Auction.project(game.events)
    assert current_player = Auction.get_current_bidder(auction)

    pass_commands =
      player_order(game.events)
      |> Players.player_order_once_around_the_table(current_player)
      |> Enum.map(&Messages.pass_on_company(&1, :red))

    game = Banana.handle_commands(game, pass_commands)

    # ASSERT
    assert length(filter_events_by_name(game.events, "company_passed")) == player_count
    assert %{company_id: :red} = fetch_single_event_payload!(game.events, "company_not_opened")
  end

  test "The player who wins the first auction starts the second auction"
  test "The order of phase 1 company auctions is :red, :blue, :green, :yellow"
  test "company_pass_rejected when auction not in progress"
  test "company_pass_rejected when player is not current bidder"
  test "company_pass_rejected when company not the current company"
  # TODO rename player_id to something like 'passing player'
end
