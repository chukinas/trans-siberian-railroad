defmodule TransSiberianRailroad.Aggregator.AuctionTest do
  use ExUnit.Case
  import TransSiberianRailroad.GameTestHelpers
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
    assert event = fetch_single_event!(events, "company_auction_started")
    assert event.payload == %{company: :red, starting_bidder: context.start_player}
  end

  describe "If all players pass on a company," do
    setup context do
      game =
        Banana.handle_commands(
          context.game,
          for player_id <- context.one_round do
            Messages.pass_on_company(player_id, :red)
          end
        )

      {:ok, game: game}
    end

    test "that company auction ends", context do
      # ARRANGE/ACT: see :game_start + above setup

      # ASSERT
      assert event = fetch_single_event!(context.game.events, "company_not_opened")
      assert event.payload == %{company_id: :red}
    end

    test "the next company auction begins with the same starting bidder", context do
      # ARRANGE/ACT: see :game_start + above setup
      start_player = context.start_player

      # ASSERT
      assert [blue_auction, _red_auction] =
               filter_events_by_name(context.game.events, "company_auction_started")

      assert %{company: :blue, starting_bidder: ^start_player} = blue_auction.payload
    end
  end

  test "The order of phase 1 company auctions is :red, :blue, :green, :yellow", context do
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
  end

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
      assert event = fetch_single_event!(game.events, "company_pass_rejected")
      assert event.payload == %{player_id: 1, company_id: :red, reason: "no auction in progress"}
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
      assert event = fetch_single_event!(game.events, "company_pass_rejected")
      assert event.payload == %{player_id: 1, company_id: :red, reason: "no auction in progress"}
    end

    test "company not the current company", context do
      # ARRANGE
      start_player = context.start_player

      # ACT
      game = Banana.handle_command(context.game, Messages.pass_on_company(start_player, :blue))

      # ASSERT
      assert event = fetch_single_event!(game.events, "company_pass_rejected")

      assert event.payload == %{
               player_id: start_player,
               company_id: :blue,
               reason: ":red is the current company"
             }
    end

    test "player is not current bidder", context do
      # ARRANGE
      start_player = context.start_player
      wrong_player = context.one_round |> Enum.drop(1) |> Enum.random()

      # ACT
      game = Banana.handle_command(context.game, Messages.pass_on_company(wrong_player, :red))

      # ASSERT
      assert event = fetch_single_event!(game.events, "company_pass_rejected")

      assert event.payload == %{
               player_id: wrong_player,
               company_id: :red,
               reason: "player #{start_player} is the current player"
             }
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
      assert event = fetch_single_event!(game.events, "bid_rejected")

      assert event.payload == %{
               player_id: start_player,
               company_id: :red,
               amount: amount,
               reason: "insufficient funds"
             }
    end
  end

  describe "when a player wins an auction" do
    setup :auction_off_company

    test "the player is charged the winning bid amount", context do
      # ARRANGE: see :start_game
      bid_winner = context.bid_winner
      start_bidder_money = current_money(context.game_prior_to_bidding, bid_winner)

      # ACT: see this descibe block's setup

      # ASSERT
      current_bidder_money = current_money(context.game, bid_winner)
      assert current_bidder_money == start_bidder_money - context.amount
    end

    test "that company's auction closes", context do
      # ARRANGE: see :start_game
      # ACT: see this descibe block's setup

      # ASSERT
      assert event = fetch_single_event!(context.game.events, "company_opened")

      assert event.payload == %{
               company_id: :red,
               player_id: context.bid_winner,
               bid_amount: context.amount
             }
    end

    test "the only valid next command is to set starting stock price"
  end

  describe "set_starting_stock_price -> starting_stock_price_rejected when" do
    setup :auction_off_company

    @tag :no_start_game_setup
    test "not in an auction phase" do
      # ARRANGE
      game = Banana.handle_commands([Messages.initialize_game(), Messages.add_player("Alice")])

      # ACT
      game = Banana.handle_command(game, Messages.set_starting_stock_price(1, :red, 10))

      # ASSERT
      assert event = fetch_single_event!(game.events, "starting_stock_price_rejected")

      assert event.payload == %{
               player_id: 1,
               company_id: :red,
               price: 10,
               reason: "no auction in progress"
             }
    end

    test "not in the correct auction substate", context do
      # ARRANGE: see :start_game setup

      # ACT
      game =
        Banana.handle_command(
          # TODO I don't like that the setup runs the auction when I don't need it.
          context.game_prior_to_bidding,
          Messages.set_starting_stock_price(1, :red, 10)
        )

      # ASSERT
      assert event = fetch_single_event!(game.events, "starting_stock_price_rejected")

      assert event.payload == %{
               player_id: 1,
               company_id: :red,
               price: 10,
               reason: "not in the correct phase of the auction"
             }
    end

    test "not the current bidder", context do
      # ARRANGE: see :start_game setup

      # ACT
      incorrect_player =
        context.one_round
        |> Enum.reject(&(&1 == context.bid_winner))
        |> Enum.random()

      game =
        Banana.handle_command(
          context.game,
          Messages.set_starting_stock_price(incorrect_player, :red, 10)
        )

      # ASSERT
      assert event = fetch_single_event!(game.events, "starting_stock_price_rejected")

      assert event.payload == %{
               player_id: incorrect_player,
               company_id: :red,
               price: 10,
               reason: "incorrect player"
             }
    end

    test "not the correct company", context do
      # ARRANGE: see :start_game setup

      # ACT
      game = Banana.handle_command(context.game, Messages.set_starting_stock_price(1, :blue, 10))

      # ASSERT
      assert event = fetch_single_event!(game.events, "starting_stock_price_rejected")

      assert event.payload == %{
               player_id: 1,
               company_id: :blue,
               price: 10,
               reason: "incorrect company"
             }
    end

    test "the price is more than the winning bid", context do
      # ARRANGE: see :start_game setup

      # ACT
      bid_winner = context.bid_winner

      game =
        Banana.handle_command(
          context.game,
          Messages.set_starting_stock_price(bid_winner, :red, 50)
        )

      # ASSERT
      assert event = fetch_single_event!(game.events, "starting_stock_price_rejected")

      assert event.payload == %{
               player_id: bid_winner,
               company_id: :red,
               price: 50,
               reason: "price exceeds winning bid"
             }
    end

    test "the price is some other invalid amount"
  end

  describe "when a player sets the starting stock price" do
    test "the next company's auction begins"
    test "The player who wins the first auction starts the second auction"
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

  defp auction_off_company(context) when not is_map_key(context, :game), do: :ok

  defp auction_off_company(context) do
    # capture state before applying the bids and passing
    game_prior_to_bidding = context.game

    bid_winner = Enum.random(context.one_round)
    amount = 8

    game =
      Banana.handle_commands(
        context.game,
        for player_id <- context.one_round do
          if player_id == bid_winner do
            Messages.submit_bid(player_id, :red, amount)
          else
            Messages.pass_on_company(player_id, :red)
          end
        end
      )

    {:ok,
     game_prior_to_bidding: game_prior_to_bidding,
     bid_winner: bid_winner,
     amount: amount,
     game: game}
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
