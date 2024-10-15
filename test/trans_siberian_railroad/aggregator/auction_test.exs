defmodule TransSiberianRailroad.Aggregator.AuctionTest do
  use ExUnit.Case
  import TransSiberianRailroad.GameTestHelpers
  alias TransSiberianRailroad.Aggregator.Auction
  alias TransSiberianRailroad.Aggregator.Players
  alias TransSiberianRailroad.Banana
  alias TransSiberianRailroad.Messages

  setup :start_game

  test "game_started -> auction_phase_started", context do
    # ARRANGE/ACT: see :start_game setup
    events = context.game.events
    assert fetch_single_event!(events, "game_started")

    # ASSERT
    assert fetch_single_event!(events, "auction_phase_started")
  end

  test "auction_phase_started -> company_auction_started", context do
    # ARRANGE/ACT: see :start_game setup
    events = context.game.events
    assert fetch_single_event!(events, "auction_phase_started")

    # ASSERT
    assert company_auction_started = fetch_single_event!(events, "company_auction_started")
    assert %{company: :red} = company_auction_started.payload
  end

  test "company_not_opened event when all players pass on a company auction", context do
    # ARRANGE
    game = context.game
    player_count = context.player_count

    # ACT
    # TODO don't test the internals of Auction
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

  test "If all players pass on a company, the next company auction begins with the same starting bidder",
       context do
    # ARRANGE
    start_player = context.start_player

    # ACT
    game =
      Banana.handle_commands(
        context.game,
        for player_id <- context.one_round do
          Messages.pass_on_company(player_id, :red)
        end
      )

    # ASSERT
    assert [blue_auction, _red_auction] =
             filter_events_by_name(game.events, "company_auction_started")

    assert %{company: :blue, starting_bidder: ^start_player} = blue_auction.payload
  end

  test "The player who wins the first auction starts the second auction"
  test "The order of phase 1 company auctions is :red, :blue, :green, :yellow"
  # TODO rename player_id to something like 'passing player'
  # TODO what happens if all players pass on all companies in phase 1?

  test "auction phase ends if all companies are passed on", context do
    # ARRANGE: see :start_game setup

    # ACT
    game =
      Banana.handle_commands(
        context.game,
        for company <- ~w/red blue green yellow/a,
            player_id <- context.one_round do
          Messages.pass_on_company(player_id, company)
        end
      )

    # ASSERT
    assert filter_events_by_name(game.events, "company_not_opened") |> length() == 4
    assert fetch_single_event!(game.events, "auction_phase_ended")
  end

  describe "passing in an auction is rejected when" do
    setup :start_game

    @tag :no_start_game_setup
    test "auction not in progress (like before the game starts)" do
      # ARRANGE
      game = Banana.handle_commands([Messages.initialize_game(), Messages.add_player("Alice")])

      # ACT
      game = Banana.handle_command(game, Messages.pass_on_company(1, :red))

      # ASSERT
      assert pass_rejected = fetch_single_event!(game.events, "company_pass_rejected")

      assert %{player_id: 1, company_id: :red, reason: "no auction in progress"} =
               pass_rejected.payload
    end

    test "auction not in progress (e.g. after end of the first auction phase)", context do
      # ARRANGE
      game =
        Banana.handle_commands(
          context.game,
          for company <- ~w/red blue green yellow/a,
              player_id <- context.one_round do
            Messages.pass_on_company(player_id, company)
          end
        )

      # ACT
      game = Banana.handle_command(game, Messages.pass_on_company(1, :red))

      # ASSERT
      assert pass_rejected = fetch_single_event!(game.events, "company_pass_rejected")

      assert %{player_id: 1, company_id: :red, reason: "no auction in progress"} =
               pass_rejected.payload
    end

    test "company not the current company", context do
      # ARRANGE
      start_player = context.start_player

      # ACT
      game = Banana.handle_command(context.game, Messages.pass_on_company(start_player, :blue))

      # ASSERT
      assert pass_rejected = fetch_single_event!(game.events, "company_pass_rejected")

      assert %{
               player_id: ^start_player,
               company_id: :blue,
               reason: "The company you're trying to pass on isn't the one being auctioned."
             } =
               pass_rejected.payload
    end

    test "player is not current bidder", context do
      # ARRANGE
      start_player = context.start_player
      wrong_player = context.one_round |> Enum.drop(1) |> Enum.random()

      # ACT
      game = Banana.handle_command(context.game, Messages.pass_on_company(wrong_player, :red))

      # ASSERT
      assert pass_rejected = fetch_single_event!(game.events, "company_pass_rejected")

      assert %{
               player_id: ^wrong_player,
               company_id: :red,
               reason: reason
             } = pass_rejected.payload

      assert reason == "It's player #{start_player}'s turn to bid on a company."
    end
  end

  describe "a bid command is rejected" do
    test "if the player does not have enough money", context do
      # ARRANGE
      start_player = context.start_player

      # ACT
      amount = 100
      game = Banana.handle_command(context.game, Messages.submit_bid(start_player, :red, amount))

      # ASSERT
      assert bid_rejected = fetch_single_event!(game.events, "bid_rejected")

      assert %{
               player_id: ^start_player,
               company_id: :red,
               amount: ^amount,
               reason: "insufficient funds"
             } = bid_rejected.payload
    end
  end

  # TODO the other thing that results from this is the closing of red's auction and the start of blue's auction
  describe "when a player wins an auction" do
    setup :start_game

    test "the player is charged the winning bid amount", context do
      # ARRANGE
      [bidder | passing_players] = context.one_round
      start_bidder_money = current_money(context.game, bidder)

      # ACT
      amount = 8
      game = Banana.handle_command(context.game, Messages.submit_bid(bidder, :red, amount))
      # and the rest pass:
      game =
        Banana.handle_commands(
          game,
          Enum.map(passing_players, &Messages.pass_on_company(&1, :red))
        )

      # ASSERT
      current_bidder_money = current_money(game, bidder)
      assert current_bidder_money == start_bidder_money - amount
    end
  end

  #########################################################
  # HELPERS
  #########################################################

  defp start_game(%{no_start_game_setup: true}), do: :ok

  defp start_game(_context) do
    player_count = Enum.random(3..5)
    start_player = Enum.random(1..player_count)
    player_order = Enum.shuffle(1..player_count)
    player_who_requested_game_start = Enum.random(1..player_count)
    one_round = Players.player_order_once_around_the_table(player_order, start_player)

    game =
      Banana.handle_commands([
        Messages.initialize_game(),
        add_player_commands(player_count),
        Messages.set_start_player(start_player),
        Messages.set_player_order(player_order),
        Messages.start_game(player_who_requested_game_start)
      ])

    {:ok,
     game: game,
     start_player: start_player,
     player_count: player_count,
     player_order: player_order,
     one_round: one_round}
  end

  defp current_money(game, player_id) do
    Enum.reduce(game.events, 0, fn event, balance ->
      case event.name do
        "money_transferred" ->
          amount = Map.get(event.payload.transfers, player_id, 0)
          balance + amount

        _ ->
          balance
      end
    end)
  end
end
