defmodule Tsr.Aggregator.AuctionPhaseTest do
  use ExUnit.Case, async: true
  import Tsr.CommandFactory
  import Tsr.GameHelpers
  import Tsr.GameTestHelpers
  alias Tsr.Constants
  alias Tsr.Messages
  alias Tsr.Players

  @phase_1_companies Constants.companies() |> Enum.take(4)
  @phase_2_companies Constants.companies() |> Enum.drop(4)

  taggable_setups()
  @moduletag :start_game

  test "auction_phase_started -> company_auction_started", context do
    # GIVEN/WHEN: see :start_game setup
    game = context.game
    assert get_one_event(game, "auction_phase_started")

    # THEN
    assert event = get_one_event(game, "company_auction_started")
    assert event.payload == %{company: "red", start_player: context.start_player}
  end

  for {phase_number, companies} <- [{1, @phase_1_companies}, {2, @phase_2_companies}] do
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
            start_player = context.start_player

            event =
              Messages.event_builder("auction_phase_started",
                phase: phase_number,
                start_player: start_player
              )

            handle_one_event(game, event)
        end

      # WHEN
      game =
        handle_commands(
          game,
          for company <- expected_companies,
              player <- context.one_round do
            pass_on_company(player, company)
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
      game = handle_one_command(game, pass_on_company(3, "red"))

      # THEN
      assert event = get_one_event(game, "company_pass_rejected")

      assert event.payload == %{
               player: 3,
               company: "red",
               reason: "no company auction in progress"
             }
    end

    test "not in auction phase (e.g. after end of the first auction phase)", context do
      # GIVEN
      game =
        handle_commands(
          context.game,
          for company <- @phase_1_companies,
              player <- context.one_round do
            pass_on_company(player, company)
          end
        )

      # WHEN
      game = handle_one_command(game, pass_on_company(1, "red"))

      # THEN
      assert event = get_one_event(game, "company_pass_rejected")

      assert event.payload == %{
               player: 1,
               company: "red",
               reason: "no company auction in progress"
             }
    end

    @tag :auction_off_company
    test "bidding is closed", context do
      # GIVEN
      # We've now auctioned off a company and are waiting for the bid winner to
      # - build the initial rail link and
      # - set the starting stock value.
      # It's no one's turn to pass on a company.
      auction_winner = context.auction_winner

      # WHEN
      game =
        handle_one_command(context.game, pass_on_company(auction_winner, "red"))

      # THEN
      assert event = get_one_event(game, "company_pass_rejected")

      assert event.payload == %{
               player: auction_winner,
               company: "red",
               reason: "bidding is closed"
             }
    end

    test "incorrect bidder", context do
      # GIVEN
      wrong_player = context.one_round |> Enum.drop(1) |> Enum.random()

      # WHEN
      # Both player and company are invalid here, but the player is the cause of the rejection.
      game =
        handle_one_command(context.game, pass_on_company(wrong_player, "blue"))

      # THEN
      assert event = get_one_event(game, "company_pass_rejected")

      assert event.payload == %{
               player: wrong_player,
               company: "blue",
               reason: "incorrect player"
             }
    end

    test "incorrect company", context do
      # GIVEN
      start_player = context.start_player

      # WHEN
      game =
        handle_one_command(context.game, pass_on_company(start_player, "blue"))

      # THEN
      assert event = get_one_event(game, "company_pass_rejected")

      assert event.payload == %{
               player: start_player,
               company: "blue",
               reason: "incorrect company"
             }
    end
  end

  describe "all_players_passed_on_company" do
    setup context do
      game =
        handle_commands(
          context.game,
          for player <- context.one_round do
            pass_on_company(player, "red")
          end
        )

      assert get_one_event(game, "all_players_passed_on_company")

      {:ok, game: game}
    end

    test "-> company_auction_started with the next company", context do
      # GIVEN/WHEN: see :game_start + above setup

      # THEN
      # Check the companies who have had their auctions started so far.
      expected_companies = ~w/red blue/

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

      assert %{company: "blue", start_player: ^start_player} = blue_auction.payload
    end

    test "-> auction_phase_ended when it's the last company", context do
      # GIVEN
      # The setup has already passed on "red", so we'll pass on the next two companies,
      # leaving just yellow to be auctioned off.
      # We haven't ended the auction phase yet.
      commands =
        for company <- ~w/blue green/,
            player <- context.one_round do
          pass_on_company(player, company)
        end

      game = handle_commands(context.game, commands)
      assert [] = filter_events(game, "auction_phase_ended")

      # WHEN
      commands =
        for player <- context.one_round do
          pass_on_company(player, "yellow")
        end

      game = handle_commands(game, commands)

      # THEN
      assert get_one_event(game, "auction_phase_ended")
    end
  end

  describe "submit_bid -> bid_rejected when" do
    test "not in auction phase", context do
      # GIVEN
      game = init_and_add_players(1)

      # WHEN
      # we put a lot of bad data into the command, but those must not be the cause of the rejection.
      wrong_player = context.one_round |> Enum.drop(1) |> Enum.random()
      game = handle_one_command(game, submit_bid(wrong_player, "blue", 0))

      # THEN
      assert event = get_one_event(game, "bid_rejected")

      assert event.payload == %{
               player: wrong_player,
               company: "blue",
               rubles: 0,
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
        handle_one_command(context.game, submit_bid(incorrect_player, "black", 0))

      # THEN
      assert event = get_one_event(game, "bid_rejected")

      assert event.payload == %{
               player: incorrect_player,
               company: "black",
               rubles: 0,
               reason: "bidding is closed"
             }
    end

    test "incorrect bidder", context do
      # GIVEN
      start_player = context.start_player
      incorrect_bidder = context.one_round |> Enum.reject(&(&1 == start_player)) |> Enum.random()

      # WHEN
      game =
        handle_one_command(context.game, submit_bid(incorrect_bidder, "blue", 0))

      # THEN
      assert event = get_one_event(game, "bid_rejected")

      assert event.payload == %{
               player: incorrect_bidder,
               company: "blue",
               rubles: 0,
               reason: "incorrect player"
             }
    end

    test "incorrect company", context do
      # GIVEN
      start_player = context.start_player

      # WHEN
      # invalid amount, but that won't cause the rejection
      game = handle_one_command(context.game, submit_bid(start_player, "blue", 0))

      # THEN
      assert event = get_one_event(game, "bid_rejected")

      assert event.payload == %{
               player: start_player,
               company: "blue",
               rubles: 0,
               reason: "incorrect company"
             }
    end

    test "rubles is less than 8", context do
      # GIVEN
      start_player = context.start_player

      # WHEN
      game = handle_one_command(context.game, submit_bid(start_player, "red", 7))

      # THEN
      assert event = get_one_event(game, "bid_rejected")

      assert event.payload == %{
               player: start_player,
               company: "red",
               rubles: 7,
               reason: "bid must be at least 8"
             }
    end

    test "bid not higher that current bid", context do
      # GIVEN
      [first_player, second_player | _] = context.one_round
      game = handle_one_command(context.game, submit_bid(first_player, "red", 8))

      # WHEN
      game = handle_one_command(game, submit_bid(second_player, "red", 8))

      # THEN
      assert event = get_one_event(game, "bid_rejected")

      assert event.payload == %{
               player: second_player,
               company: "red",
               rubles: 8,
               reason: "bid must be higher than the current bid"
             }
    end

    test "insufficient funds", context do
      # GIVEN
      start_player = context.start_player

      # WHEN
      rubles = 100

      game =
        handle_one_command(context.game, submit_bid(start_player, "red", rubles))

      # THEN
      assert event = get_one_event(game, "bid_rejected")

      assert event.payload == %{
               player: start_player,
               company: "red",
               rubles: rubles,
               reason: "insufficient funds"
             }
    end
  end

  describe "player_won_company_auction" do
    @describetag :auction_off_company

    test "-> auction_winner is charged the winning bid rubles", context do
      # GIVEN: see :start_game
      auction_winner = context.auction_winner
      start_player = current_money(context.game_prior_to_bidding, auction_winner)
      game = context.game

      # WHEN: see this descibe block's setup

      # THEN
      current_bidder_money = current_money(game, auction_winner)
      assert current_bidder_money == start_player - context.rubles

      assert event = get_latest_event(game, "rubles_transferred")
      assert event.payload.reason == "company stock auctioned off"
    end

    test "-> awaiting_stock_value", context do
      # GIVEN: see :start_game, :auction_off_company
      auction_winner = context.auction_winner
      game = context.game

      # WHEN: see this descibe block's setup

      # THEN
      assert event = get_one_event(game, "awaiting_stock_value")

      assert event.payload == %{
               player: auction_winner,
               company: "red",
               max_stock_value: 8
             }
    end

    test "-> awaiting_initial_rail_link", context do
      # GIVEN: see :start_game
      auction_winner = context.auction_winner
      game = context.game

      # WHEN: see this descibe block's setup

      # THEN
      assert event = get_one_event(game, "awaiting_initial_rail_link")

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
               company: "red",
               available_links: available_links
             }
    end

    test "-> player_won_company_auction", context do
      # GIVEN: see :start_game
      # WHEN: see this descibe block's setup
      game = context.game

      # THEN
      assert event = get_one_event(game, "player_won_company_auction")

      assert event.payload == %{
               company: "red",
               player: context.auction_winner,
               rubles: context.rubles
             }
    end

    test "has only build_initial_rail_link and set_stock_value as valid followup commands",
         context do
      # GIVEN a player has won a company auction
      game = context.game
      auction_winner = context.auction_winner

      # WHEN the player tries to pass or bid,
      for {resulting_event, command} <- [
            {"company_pass_rejected", pass_on_company(auction_winner, "blue")},
            {"bid_rejected", submit_bid(auction_winner, "blue", 8)},
            {"initial_rail_link_built",
             build_initial_rail_link(auction_winner, "red", ["moscow", "nizhnynovgorod"])},
            {"stock_value_set", set_stock_value(auction_winner, "red", 8)}
          ] do
        # THEN the command is rejected
        refute get_latest_event(game, resulting_event)
        game = handle_one_command(game, command)
        assert get_one_event(game, resulting_event)
      end
    end
  end

  describe "build_initial_rail_link -> initial_rail_link_rejected when" do
    @describetag :start_game
    @describetag :auction_off_company

    @tag start_game: false
    @tag auction_off_company: false
    test "no company auction in progress" do
      # GIVEN we're still setting the game up (and not in a company auction),
      game = init_and_add_players(1)

      # WHEN we try building a rail link with completely invalid data,
      rail_link = ["philly", "newyork"]
      game = handle_one_command(game, build_initial_rail_link(2, "blue", rail_link))

      # THEN the command is rejected for reasons other than the invalid data.
      assert event = get_one_event(game, "initial_rail_link_rejected")

      assert event.payload == %{
               player: 2,
               company: "blue",
               rail_link: rail_link,
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
        build_initial_rail_link(wrong_player, "blue", ["invalid rail link"])
        |> injest_commands(game)

      # THEN the command is rejected because of the wrong player,
      # regardless of the other invalid data.
      assert event = get_one_event(game, "initial_rail_link_rejected")

      assert event.payload == %{
               player: wrong_player,
               company: "blue",
               rail_link: ["invalid rail link"],
               reason: "incorrect player"
             }
    end

    test "wrong company", context do
      # GIVEN a player just won a company auction and we're awaiting a rail link,
      game = context.game
      auction_winner = context.auction_winner
      wrong_company = "blue"

      # WHEN the player tries to build a rail link for the wrong company
      # and with invalid rail_link,
      game =
        build_initial_rail_link(auction_winner, wrong_company, ["invalid rail link"])
        |> injest_commands(game)

      # THEN the command is rejected because of the wrong company.
      assert event = get_one_event(game, "initial_rail_link_rejected")

      assert event.payload == %{
               player: auction_winner,
               company: wrong_company,
               rail_link: ["invalid rail link"],
               reason: "incorrect company"
             }
    end

    test "invalid rail link", context do
      # GIVEN a player just won a company auction and we're awaiting a rail link,
      game = context.game
      auction_winner = context.auction_winner

      # WHEN the player tries to build a rail link with invalid rail link,
      for {invalid_rail_link, _} <- [
            {~w(stpetersburg moscow),
             reason: "these cities are **valid**, but not in alphabetical order"},
            {["moscow", "nizhnynovgorod", "invalid"], reason: "list contains a non-existant city"}
          ] do
        game =
          build_initial_rail_link(auction_winner, "red", invalid_rail_link)
          |> injest_commands(game)

        # THEN the command is rejected
        assert event = get_one_event(game, "initial_rail_link_rejected")

        assert event.payload == %{
                 player: auction_winner,
                 company: "red",
                 rail_link: invalid_rail_link,
                 reason: "invalid rail link"
               }
      end
    end

    @tag :simple_setup
    test "link has already been built", context do
      # GIVEN the "red" auction in already done
      game = context.game
      auction_winner = context.auction_winner
      assert event = get_latest_event(game, "awaiting_initial_rail_link")
      rail_link = Enum.random(event.payload.available_links)

      game =
        [
          build_initial_rail_link(auction_winner, "red", rail_link),
          set_stock_value(auction_winner, "red", 8)
        ]
        |> injest_commands(game)

      # AND "blue" is just auctioned off

      [^auction_winner, passer, next_auction_winner] =
        Players.one_round(context.player_order, auction_winner)

      game =
        [
          pass_on_company(auction_winner, "blue"),
          pass_on_company(passer, "blue"),
          submit_bid(next_auction_winner, "blue", 8)
        ]
        |> injest_commands(game)

      # WHEN the auction winner tries to build the same link again,
      game =
        build_initial_rail_link(next_auction_winner, "blue", rail_link) |> injest_commands(game)

      # THEN the command is rejected
      assert event = get_one_event(game, "initial_rail_link_rejected")

      assert event.payload == %{
               player: next_auction_winner,
               company: "blue",
               rail_link: rail_link,
               reason: "link already built"
             }

      # AND that link wasn't in the prompt command anyway
      assert event = get_latest_event(game, "awaiting_initial_rail_link")
      assert rail_link not in event.payload.available_links
    end

    test "unconnected rail link", context do
      # GIVEN "red" just got auctioned off
      game = context.game
      auction_winner = context.auction_winner

      # WHEN we try building a link that's not connected to Moscow,
      unconnected_link = ~w(chita ext_chita)

      game =
        build_initial_rail_link(auction_winner, "red", unconnected_link)
        |> injest_commands(game)

      # THEN the command is rejected
      assert event = get_one_event(game, "initial_rail_link_rejected")

      assert event.payload == %{
               player: auction_winner,
               company: "red",
               rail_link: unconnected_link,
               reason: "unconnected rail link"
             }
    end
  end

  describe "build_initial_rail_link -> initial_rail_link_built" do
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
      game = handle_one_command(game, set_stock_value(1, "red", 10))

      # THEN
      assert event = get_one_event(game, "stock_value_rejected")

      assert event.payload == %{
               player: 1,
               company: "red",
               stock_value: 10,
               reason: "no company auction in progress"
             }
    end

    @tag auction_off_company: false
    test "bidding is closed", context do
      # GIVEN: see :start_game setup

      # WHEN
      command = set_stock_value(1, "red", 10)
      game = handle_one_command(context.game, command)

      # THEN
      assert event = get_one_event(game, "stock_value_rejected")

      assert event.payload == %{
               player: 1,
               company: "red",
               stock_value: 10,
               reason: "not awaiting stock value"
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
          set_stock_value(incorrect_player, "red", 10)
        )

      # THEN
      assert event = get_one_event(game, "stock_value_rejected")

      assert event.payload == %{
               player: incorrect_player,
               company: "red",
               stock_value: 10,
               reason: "incorrect player"
             }
    end

    test "incorrect company", context do
      # GIVEN: see :start_game setup
      auction_winner = context.auction_winner

      # WHEN
      command = set_stock_value(auction_winner, "blue", 7)
      game = handle_one_command(context.game, command)

      # THEN
      assert event = get_one_event(game, "stock_value_rejected")

      assert event.payload == %{
               player: auction_winner,
               company: "blue",
               stock_value: 7,
               reason: "incorrect company"
             }
    end

    @tag winning_bid_amount: 10
    test "the stock value is more than the winning bid", context do
      # GIVEN: see :start_game setup

      # WHEN
      auction_winner = context.auction_winner

      game =
        handle_one_command(
          context.game,
          set_stock_value(auction_winner, "red", 50)
        )

      # THEN
      assert event = get_one_event(game, "stock_value_rejected")

      assert event.payload == %{
               player: auction_winner,
               company: "red",
               stock_value: 50,
               reason: "stock value exceeds winning bid"
             }
    end

    @tag winning_bid_amount: 16
    test "invalid rubles", context do
      # GIVEN: see :start_game setup

      # WHEN
      auction_winner = context.auction_winner

      game =
        handle_one_command(
          context.game,
          set_stock_value(auction_winner, "red", 9)
        )

      # THEN
      assert event = get_one_event(game, "stock_value_rejected")

      assert event.payload == %{
               player: auction_winner,
               company: "red",
               stock_value: 9,
               reason: "not one of the valid stock values"
             }
    end
  end

  describe "company_auction_ended" do
    @describetag :auction_off_company

    @tag :simple_setup
    @tag auction_off_company: false
    test "after both initial_rail_link_build and stock_value_set come in", context do
      # GIVEN
      game = context.game

      commands = [
        pass_on_company(1, "red"),
        pass_on_company(2, "red"),
        submit_bid(3, "red", 8)
      ]

      game = handle_commands(game, commands)
      assert get_one_event(game, "awaiting_initial_rail_link")
      assert get_one_event(game, "awaiting_stock_value")
      refute get_latest_event(game, "company_auction_ended")

      [command1, command2] =
        Enum.shuffle([
          set_stock_value(3, "red", 8),
          build_initial_rail_link(3, "red", ["moscow", "nizhnynovgorod"])
        ])

      # WHEN the first command comes in, the the auction is still ongoing, but ...
      game = handle_one_command(game, command1)
      refute get_latest_event(game, "company_auction_ended")

      # WHEN the second command comes in...
      game = handle_one_command(game, command2)

      # THEN the company auction finally ends.
      assert get_one_event(game, "company_auction_ended")
    end

    test "starts the next company's auction", context do
      # GIVEN
      game = context.game
      auction_winner = context.auction_winner

      # WHEN
      game =
        [
          set_stock_value(auction_winner, "red", 8),
          build_initial_rail_link(auction_winner, "red", ["moscow", "nizhnynovgorod"])
        ]
        |> Enum.shuffle()
        |> injest_commands(game)

      # THEN
      events = filter_events(game, "company_auction_started", asc: true)
      assert ~w/red blue/ == Enum.map(events, & &1.payload.company)
    end

    @tag start_player: 1
    @tag auction_winner: 2
    test "The player who wins the first auction starts the second auction", context do
      # GIVEN
      game = context.game

      game =
        [
          build_initial_rail_link(2, "red", ["moscow", "nizhnynovgorod"]),
          set_stock_value(2, "red", 8)
        ]
        |> Enum.shuffle()
        |> injest_commands(game)

      # WHEN
      game =
        pass_on_company(2, "blue")
        |> injest_commands(game)

      # THEN
      assert event = get_latest_event(game, "company_passed")
      assert event.payload == %{company: "blue", player: 2}
    end

    @tag auction_off_company: false
    test "-> auction_phase_ended when it's the last company", context do
      # GIVEN
      # All players pass on all companies except for the last player on the last company
      auction_winner = Enum.at(context.one_round, -1)

      commands =
        for company <- @phase_1_companies,
            player <- context.one_round do
          pass_on_company(player, company)
        end

      commands =
        List.update_at(commands, -1, fn _command ->
          submit_bid(auction_winner, "yellow", 8)
        end)

      game = handle_commands(context.game, commands)

      # WHEN
      game =
        [
          build_initial_rail_link(auction_winner, "yellow", ["moscow", "nizhnynovgorod"]),
          set_stock_value(auction_winner, "yellow", 8)
        ]
        |> injest_commands(game)

      assert get_one_event(game, "initial_rail_link_built")
      assert get_one_event(game, "stock_value_set")

      # THEN
      assert event = get_one_event(game, "auction_phase_ended")
      assert event.payload == %{phase: 1, start_player: auction_winner}
    end
  end
end
