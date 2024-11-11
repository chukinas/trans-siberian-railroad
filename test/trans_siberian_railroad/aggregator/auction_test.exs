defmodule TransSiberianRailroad.Aggregator.AuctionTest do
  use ExUnit.Case, async: true
  import TransSiberianRailroad.CommandFactory
  import TransSiberianRailroad.GameHelpers
  import TransSiberianRailroad.GameTestHelpers
  alias TransSiberianRailroad.Messages
  alias TransSiberianRailroad.Metadata
  alias TransSiberianRailroad.Players

  taggable_setups()
  @moduletag :start_game

  test "auction_phase_started -> company_auction_started", context do
    # GIVEN/WHEN: see :start_game setup
    game = context.game
    assert fetch_single_event!(game, "auction_phase_started")

    # THEN
    assert event = fetch_single_event!(game, "company_auction_started")
    assert event.payload == %{company: :red, start_bidder: context.start_player}
  end

  for {phase_number, companies} <- [{1, ~w/red blue green yellow/a}, {2, ~w/black white/a}] do
    test "Phase #{phase_number} companies are auction in this order: #{inspect(companies)}",
         context do
      # GIVEN
      # We'll start the game, which kicks off the phase-1 auction.
      # But then we'll "cheat" and re-issue an auction_phase_started event with the phase_number we care about for this test.
      expected_companies = unquote(companies)

      game =
        case unquote(phase_number) do
          1 ->
            context.game

          2 = phase_number ->
            game = context.game
            start_bidder = context.start_player
            [last_event | _] = game.events
            metadata = Metadata.new(last_event.version + 1, Ecto.UUID.generate())
            event = Messages.auction_phase_started(phase_number, start_bidder, metadata)
            handle_one_event(game, event)
        end

      # WHEN
      game =
        handle_commands(
          game,
          for company <- expected_companies,
              player_id <- context.one_round do
            pass_on_company(player_id, company)
          end
        )

      # THEN
      actual_companies =
        filter_events(game, "all_players_passed_on_company", asc: true)
        |> Enum.map(& &1.payload.company)

      assert actual_companies == expected_companies
    end
  end

  describe "pass_on_company -> company_pass_rejected when" do
    @tag start_game: false
    test "not in auction phase (like before the game starts)" do
      # GIVEN
      game = init_and_add_players(2)

      # WHEN
      game = handle_one_command(game, pass_on_company(3, :red))

      # THEN
      assert event = fetch_single_event!(game, "company_pass_rejected")

      assert event.payload == %{
               passing_player: 3,
               company: :red,
               reason: "no company auction in progress"
             }
    end

    test "not in auction phase (e.g. after end of the first auction phase)", context do
      # GIVEN
      game =
        handle_commands(
          context.game,
          for company <- ~w/red blue green yellow/a,
              player_id <- context.one_round do
            pass_on_company(player_id, company)
          end
        )

      # WHEN
      game = handle_one_command(game, pass_on_company(1, :red))

      # THEN
      assert event = fetch_single_event!(game, "company_pass_rejected")

      assert event.payload == %{
               passing_player: 1,
               company: :red,
               reason: "no company auction in progress"
             }
    end

    @tag :auction_off_company
    test "bidding is closed", context do
      # GIVEN
      # We've now auctioned off a company and are waiting for the bid winner to
      # - build the initial rail link and
      # - set the starting stock price.
      # It's no one's turn to pass on a company.
      auction_winner = context.auction_winner

      # WHEN
      game =
        handle_one_command(context.game, pass_on_company(auction_winner, :red))

      # THEN
      assert event = fetch_single_event!(game, "company_pass_rejected")

      assert event.payload == %{
               passing_player: auction_winner,
               company: :red,
               reason: "bidding is closed"
             }
    end

    test "incorrect bidder", context do
      # GIVEN
      wrong_player = context.one_round |> Enum.drop(1) |> Enum.random()

      # WHEN
      # Both player and company are invalid here, but the player is the cause of the rejection.
      game =
        handle_one_command(context.game, pass_on_company(wrong_player, :blue))

      # THEN
      assert event = fetch_single_event!(game, "company_pass_rejected")

      assert event.payload == %{
               passing_player: wrong_player,
               company: :blue,
               reason: "incorrect player"
             }
    end

    test "incorrect company", context do
      # GIVEN
      start_player = context.start_player

      # WHEN
      game =
        handle_one_command(context.game, pass_on_company(start_player, :blue))

      # THEN
      assert event = fetch_single_event!(game, "company_pass_rejected")

      assert event.payload == %{
               passing_player: start_player,
               company: :blue,
               reason: "incorrect company"
             }
    end
  end

  describe "all_players_passed_on_company" do
    setup context do
      game =
        handle_commands(
          context.game,
          for player_id <- context.one_round do
            pass_on_company(player_id, :red)
          end
        )

      assert fetch_single_event!(game, "all_players_passed_on_company")

      {:ok, game: game}
    end

    test "-> company_auction_started with the next company", context do
      # GIVEN/WHEN: see :game_start + above setup

      # THEN
      # Check the companies who have had their auctions started so far.
      expected_companies = ~w/red blue/a

      actual_companies =
        filter_events(context.game, "company_auction_started", asc: true)
        |> Enum.map(& &1.payload.company)

      assert expected_companies == actual_companies
    end

    test "-> company_auction_started with the same start bidder", context do
      # GIVEN/WHEN: see :game_start + above setup
      start_player = context.start_player

      # THEN
      assert [blue_auction, _red_auction] =
               filter_events(context.game, "company_auction_started")

      assert %{company: :blue, start_bidder: ^start_player} = blue_auction.payload
    end

    test "-> auction_phase_ended when it's the last company", context do
      # GIVEN
      # The setup has already passed on :red, so we'll pass on the next two companies,
      # leaving just yellow to be auctioned off.
      # We haven't ended the auction phase yet.
      commands =
        for company <- ~w/blue green/a,
            player_id <- context.one_round do
          pass_on_company(player_id, company)
        end

      game = handle_commands(context.game, commands)
      assert [] = filter_events(game, "auction_phase_ended")

      # WHEN
      commands =
        for player_id <- context.one_round do
          pass_on_company(player_id, :yellow)
        end

      game = handle_commands(game, commands)

      # THEN
      assert fetch_single_event!(game, "auction_phase_ended")
    end
  end

  describe "submit_bid -> bid_rejected when" do
    test "not in auction phase", context do
      # GIVEN
      game = init_and_add_players(1)

      # WHEN
      # we put a lot of bad data into the command, but those must not be the cause of the rejection.
      wrong_player = context.one_round |> Enum.drop(1) |> Enum.random()
      game = handle_one_command(game, submit_bid(wrong_player, :blue, 0))

      # THEN
      assert event = fetch_single_event!(game, "bid_rejected")

      assert event.payload == %{
               bidder: wrong_player,
               company: :blue,
               amount: 0,
               reason: "no company auction in progress"
             }
    end

    @tag :auction_off_company
    test "bidding is closed", context do
      # GIVEN
      auction_winner = context.auction_winner

      # WHEN
      incorrect_player =
        context.one_round |> Enum.reject(&(&1 == auction_winner)) |> Enum.random()

      game =
        handle_one_command(context.game, submit_bid(incorrect_player, :black, 0))

      # THEN
      assert event = fetch_single_event!(game, "bid_rejected")

      assert event.payload == %{
               bidder: incorrect_player,
               company: :black,
               amount: 0,
               reason: "bidding is closed"
             }
    end

    test "incorrect bidder", context do
      # GIVEN
      start_player = context.start_player
      incorrect_bidder = context.one_round |> Enum.reject(&(&1 == start_player)) |> Enum.random()

      # WHEN
      game =
        handle_one_command(context.game, submit_bid(incorrect_bidder, :blue, 0))

      # THEN
      assert event = fetch_single_event!(game, "bid_rejected")

      assert event.payload == %{
               bidder: incorrect_bidder,
               company: :blue,
               amount: 0,
               reason: "incorrect player"
             }
    end

    test "incorrect company", context do
      # GIVEN
      start_player = context.start_player

      # WHEN
      # invalid amount, but that won't cause the rejection
      game = handle_one_command(context.game, submit_bid(start_player, :blue, 0))

      # THEN
      assert event = fetch_single_event!(game, "bid_rejected")

      assert event.payload == %{
               bidder: start_player,
               company: :blue,
               amount: 0,
               reason: "incorrect company"
             }
    end

    test "amount is less than 8", context do
      # GIVEN
      start_player = context.start_player

      # WHEN
      game = handle_one_command(context.game, submit_bid(start_player, :red, 7))

      # THEN
      assert event = fetch_single_event!(game, "bid_rejected")

      assert event.payload == %{
               bidder: start_player,
               company: :red,
               amount: 7,
               reason: "bid must be at least 8"
             }
    end

    test "bid not higher that current bid", context do
      # GIVEN
      [first_player, second_player | _] = context.one_round
      game = handle_one_command(context.game, submit_bid(first_player, :red, 8))

      # WHEN
      game = handle_one_command(game, submit_bid(second_player, :red, 8))

      # THEN
      assert event = fetch_single_event!(game, "bid_rejected")

      assert event.payload == %{
               bidder: second_player,
               company: :red,
               amount: 8,
               reason: "bid must be higher than the current bid"
             }
    end

    test "insufficient funds", context do
      # GIVEN
      start_player = context.start_player

      # WHEN
      amount = 100

      game =
        handle_one_command(context.game, submit_bid(start_player, :red, amount))

      # THEN
      assert event = fetch_single_event!(game, "bid_rejected")

      assert event.payload == %{
               bidder: start_player,
               company: :red,
               amount: amount,
               reason: "insufficient funds"
             }
    end
  end

  describe "player_won_company_auction" do
    @describetag :auction_off_company

    test "-> auction_winner is charged the winning bid amount", context do
      # GIVEN: see :start_game
      auction_winner = context.auction_winner
      start_bidder_money = current_money(context.game_prior_to_bidding, auction_winner)
      game = context.game

      # WHEN: see this descibe block's setup

      # THEN
      current_bidder_money = current_money(game, auction_winner)
      assert current_bidder_money == start_bidder_money - context.amount

      assert event = get_latest_event(game, "money_transferred")
      assert event.payload.reason == "company stock auctioned off"
    end

    test "-> awaiting_stock_value", context do
      # GIVEN: see :start_game, :auction_off_company
      auction_winner = context.auction_winner
      game = context.game

      # WHEN: see this descibe block's setup

      # THEN
      assert event = fetch_single_event!(game, "awaiting_stock_value")

      assert event.payload == %{
               player: auction_winner,
               company: :red,
               max_price: 8
             }
    end

    test "-> awaiting_rail_link", context do
      # GIVEN: see :start_game
      auction_winner = context.auction_winner
      game = context.game

      # WHEN: see this descibe block's setup

      # THEN
      assert event = fetch_single_event!(game, "awaiting_rail_link")

      available_links = [
        ["bryansk", "moscow"],
        ["kazan", "moscow"],
        ["moscow", "nizhnynovgorod"],
        ["moscow", "oryol"],
        ["moscow", "samara"],
        ["moscow", "saratov"],
        ["moscow", "smolensk"],
        ["moscow", "stpetersburg"],
        ["moscow", "voronezh"],
        ["moscow", "yaroslavl"]
      ]

      assert event.payload == %{
               player: auction_winner,
               company: :red,
               available_links: available_links
             }
    end

    test "-> player_won_company_auction", context do
      # GIVEN: see :start_game
      # WHEN: see this descibe block's setup
      game = context.game

      # THEN
      assert event = fetch_single_event!(game, "player_won_company_auction")

      assert event.payload == %{
               company: :red,
               auction_winner: context.auction_winner,
               bid_amount: context.amount
             }
    end

    test "has only build_rail_link and set_stock_value as valid followup commands", context do
      # GIVEN a player has won a company auction
      game = context.game
      auction_winner = context.auction_winner

      # WHEN the player tries to pass or bid,
      for {resulting_event, command} <- [
            {"company_pass_rejected", pass_on_company(auction_winner, :blue)},
            {"bid_rejected", submit_bid(auction_winner, :blue, 8)},
            {"rail_link_built",
             build_rail_link(auction_winner, :red, ["moscow", "nizhnynovgorod"])},
            {"stock_value_set", set_stock_value(auction_winner, :red, 8)}
          ] do
        # THEN the command is rejected
        refute get_latest_event(game, resulting_event)
        game = handle_one_command(game, command)
        assert fetch_single_event!(game, resulting_event)
      end
    end
  end

  describe "build_rail_link -> rail_link_rejected when" do
    @describetag :start_game
    @describetag :auction_off_company

    @tag start_game: false
    @tag auction_off_company: false
    test "no company auction in progress" do
      # GIVEN we're still setting the game up (and not in a company auction),
      game = init_and_add_players(1)

      # WHEN we try building a rail link with completely invalid data,
      cities = ["philly", "newyork"]
      game = handle_one_command(game, build_rail_link(2, :blue, cities))

      # THEN the command is rejected for reasons other than the invalid data.
      assert event = fetch_single_event!(game, "rail_link_rejected")

      assert event.payload == %{
               player: 2,
               company: :blue,
               cities: cities,
               reason: "no company auction in progress"
             }
    end

    test "wrong player", context do
      # GIVEN a player just won a company auction and we're awaiting a rail link,
      game = context.game
      auction_winner = context.auction_winner
      wrong_player = context.one_round |> Enum.reject(&(&1 == auction_winner)) |> Enum.random()

      # WHEN the wrong player tries to build a rail link,
      game =
        build_rail_link(wrong_player, :blue, ["invalid city"])
        |> injest_commands(game)

      # THEN the command is rejected because of the wrong player,
      # regardless of the other invalid data.
      assert event = fetch_single_event!(game, "rail_link_rejected")

      assert event.payload == %{
               player: wrong_player,
               company: :blue,
               cities: ["invalid city"],
               reason: "incorrect player"
             }
    end

    test "wrong company", context do
      # GIVEN a player just won a company auction and we're awaiting a rail link,
      game = context.game
      auction_winner = context.auction_winner
      wrong_company = :blue

      # WHEN the player tries to build a rail link for the wrong company
      # and with invalid cities,
      game =
        build_rail_link(auction_winner, wrong_company, ["invalid city"])
        |> injest_commands(game)

      # THEN the command is rejected because of the wrong company.
      assert event = fetch_single_event!(game, "rail_link_rejected")

      assert event.payload == %{
               player: auction_winner,
               company: wrong_company,
               cities: ["invalid city"],
               reason: "incorrect company"
             }
    end

    test "invalid cities", context do
      # GIVEN a player just won a company auction and we're awaiting a rail link,
      game = context.game
      auction_winner = context.auction_winner

      # WHEN the player tries to build a rail link with invalid cities,
      for {invalid_cities, _} <- [
            {~w(stpetersburg moscow),
             reason: "these cities are **valid**, but not in alphabetical order"},
            {["moscow", "nizhnynovgorod", "invalid"], reason: "list contains a non-existant city"}
          ] do
        game =
          build_rail_link(auction_winner, :red, invalid_cities)
          |> injest_commands(game)

        # THEN the command is rejected
        assert event = fetch_single_event!(game, "rail_link_rejected")

        assert event.payload == %{
                 player: auction_winner,
                 company: :red,
                 cities: invalid_cities,
                 reason: "invalid cities"
               }
      end
    end

    @tag :simple_setup
    test "link has already been built", context do
      # GIVEN the :red auction in already done
      game = context.game
      auction_winner = context.auction_winner
      cities = ["moscow", "nizhnynovgorod"]

      game =
        [
          build_rail_link(auction_winner, :red, cities),
          set_stock_value(auction_winner, :red, 8)
        ]
        |> injest_commands(game)

      # AND :blue is just auctioned off

      [^auction_winner, passer, next_auction_winner] =
        Players.one_round(context.player_order, auction_winner)

      game =
        [
          pass_on_company(auction_winner, :blue),
          pass_on_company(passer, :blue),
          submit_bid(next_auction_winner, :blue, 8)
        ]
        |> injest_commands(game)

      # WHEN the auction winner tries to build the same link again,
      game = build_rail_link(next_auction_winner, :blue, cities) |> injest_commands(game)

      # THEN the command is rejected
      assert event = fetch_single_event!(game, "rail_link_rejected")

      assert event.payload == %{
               player: next_auction_winner,
               company: :blue,
               cities: cities,
               reason: "link already built"
             }
    end

    test "not connected to existing rail network"
    test "link not connected to existing rail network"
  end

  describe "build_rail_link -> rail_link_built" do
    test "does not by itself end the auction phase (stock_value_set is also needed)"
  end

  describe "set_stock_value -> stock_value_rejected when" do
    @describetag :auction_off_company

    @tag start_game: false
    @tag auction_off_company: false
    test "not in company auction" do
      # GIVEN
      game = init_and_add_players(1)

      # WHEN
      game = handle_one_command(game, set_stock_value(1, :red, 10))

      # THEN
      assert event = fetch_single_event!(game, "stock_value_rejected")

      assert event.payload == %{
               auction_winner: 1,
               company: :red,
               price: 10,
               reason: "no company auction in progress"
             }
    end

    @tag auction_off_company: false
    test "bidding is closed", context do
      # GIVEN: see :start_game setup

      # WHEN
      command = set_stock_value(1, :red, 10)
      game = handle_one_command(context.game, command)

      # THEN
      assert event = fetch_single_event!(game, "stock_value_rejected")

      assert event.payload == %{
               auction_winner: 1,
               company: :red,
               price: 10,
               reason: "not awaiting stock price"
             }
    end

    test "incorrect bidder", context do
      # GIVEN: see :start_game setup

      # WHEN
      incorrect_player =
        context.one_round
        |> Enum.reject(&(&1 == context.auction_winner))
        |> Enum.random()

      game =
        handle_one_command(
          context.game,
          set_stock_value(incorrect_player, :red, 10)
        )

      # THEN
      assert event = fetch_single_event!(game, "stock_value_rejected")

      assert event.payload == %{
               auction_winner: incorrect_player,
               company: :red,
               price: 10,
               reason: "incorrect player"
             }
    end

    test "incorrect company", context do
      # GIVEN: see :start_game setup
      auction_winner = context.auction_winner

      # WHEN
      command = set_stock_value(auction_winner, :blue, 7)
      game = handle_one_command(context.game, command)

      # THEN
      assert event = fetch_single_event!(game, "stock_value_rejected")

      assert event.payload == %{
               auction_winner: auction_winner,
               company: :blue,
               price: 7,
               reason: "incorrect company"
             }
    end

    @tag winning_bid_amount: 10
    test "the price is more than the winning bid", context do
      # GIVEN: see :start_game setup

      # WHEN
      auction_winner = context.auction_winner

      game =
        handle_one_command(
          context.game,
          set_stock_value(auction_winner, :red, 50)
        )

      # THEN
      assert event = fetch_single_event!(game, "stock_value_rejected")

      assert event.payload == %{
               auction_winner: auction_winner,
               company: :red,
               price: 50,
               reason: "price exceeds winning bid"
             }
    end

    @tag winning_bid_amount: 16
    test "invalid amount", context do
      # GIVEN: see :start_game setup

      # WHEN
      auction_winner = context.auction_winner

      game =
        handle_one_command(
          context.game,
          set_stock_value(auction_winner, :red, 9)
        )

      # THEN
      assert event = fetch_single_event!(game, "stock_value_rejected")

      assert event.payload == %{
               auction_winner: auction_winner,
               company: :red,
               price: 9,
               reason: "not one of the valid stock prices"
             }
    end
  end

  describe "company_auction_ended" do
    @describetag :auction_off_company

    @tag :simple_setup
    @tag auction_off_company: false
    test "after both rail_link_build and stock_value_set come in", context do
      # GIVEN
      game = context.game

      commands = [
        pass_on_company(1, :red),
        pass_on_company(2, :red),
        submit_bid(3, :red, 8)
      ]

      game = handle_commands(game, commands)
      assert fetch_single_event!(game, "awaiting_rail_link")
      assert fetch_single_event!(game, "awaiting_stock_value")
      refute get_latest_event(game, "company_auction_ended")

      [command1, command2] =
        Enum.shuffle([
          set_stock_value(3, :red, 8),
          build_rail_link(3, :red, ["moscow", "nizhnynovgorod"])
        ])

      # WHEN the first command comes in, the the auction is still ongoing, but ...
      game = handle_one_command(game, command1)
      refute get_latest_event(game, "company_auction_ended")

      # WHEN the second command comes in...
      game = handle_one_command(game, command2)

      # THEN the company auction finally ends.
      assert fetch_single_event!(game, "company_auction_ended")
    end

    test "starts the next company's auction", context do
      # GIVEN
      game = context.game
      auction_winner = context.auction_winner

      # WHEN
      game =
        [
          set_stock_value(auction_winner, :red, 8),
          build_rail_link(auction_winner, :red, ["moscow", "nizhnynovgorod"])
        ]
        |> Enum.shuffle()
        |> injest_commands(game)

      # THEN
      events = filter_events(game, "company_auction_started", asc: true)
      assert ~w/red blue/a == Enum.map(events, & &1.payload.company)
    end

    @tag start_player: 1
    @tag auction_winner: 2
    test "The player who wins the first auction starts the second auction", context do
      # GIVEN
      game = context.game

      game =
        [
          build_rail_link(2, :red, ["moscow", "nizhnynovgorod"]),
          set_stock_value(2, :red, 8)
        ]
        |> Enum.shuffle()
        |> injest_commands(game)

      # WHEN
      game =
        pass_on_company(2, :blue)
        |> injest_commands(game)

      # THEN
      assert event = get_latest_event(game, "company_passed")
      assert event.payload == %{company: :blue, passing_player: 2}
    end

    @tag auction_off_company: false
    test "-> auction_phase_ended when it's the last company", context do
      # GIVEN
      # All players pass on all companies except for the last player on the last company
      auction_winner = Enum.at(context.one_round, -1)

      commands =
        for company <- ~w/red blue green yellow/a,
            player <- context.one_round do
          pass_on_company(player, company)
        end

      commands =
        List.update_at(commands, -1, fn _command ->
          submit_bid(auction_winner, :yellow, 8)
        end)

      game = handle_commands(context.game, commands)

      # WHEN
      game =
        [
          build_rail_link(auction_winner, :yellow, ["moscow", "nizhnynovgorod"]),
          set_stock_value(auction_winner, :yellow, 8)
        ]
        |> injest_commands(game)

      assert fetch_single_event!(game, "rail_link_built")
      assert fetch_single_event!(game, "stock_value_set")

      # THEN
      assert event = fetch_single_event!(game, "auction_phase_ended")
      assert event.payload == %{phase_number: 1, start_player: auction_winner}
    end
  end
end
