defmodule TransSiberinteanRailroad.Aggregator.PlayerTurnTest do
  use ExUnit.Case, async: true
  import TransSiberianRailroad.CommandFactory
  import TransSiberianRailroad.GameHelpers
  import TransSiberianRailroad.GameTestHelpers
  alias TransSiberianRailroad.Messages

  taggable_setups()

  @incorrect_price 76

  #########################################################
  # Start Turn
  #########################################################

  describe "start_player_turn" do
    @describetag :start_game
    test "-> player_turn_started", context do
      # GIVEN all player pass on all companies, except for the last player on the last company
      {final_pass, pass_commands} =
        for company <- ~w/red blue green yellow/a,
            player <- context.one_round do
          pass_on_company(player, company)
        end
        |> List.pop_at(-1)

      game = context.game
      game = handle_commands(game, pass_commands)
      refute Enum.find(game.events, &String.contains?(&1.name, "reject"))

      # WHEN that last player passes on the last company
      game = handle_one_command(game, final_pass)
      refute Enum.find(game.events, &String.contains?(&1.name, "reject"))

      # THEN the start player's turn begins
      assert event = fetch_single_event!(game, "player_turn_started")
      assert event.payload == %{player: context.start_player}
    end

    test "-> player_turn_rejected", context do
      # GIVEN a player's turn is already in progress (in this case, the first player's turn)
      commands =
        for company <- ~w/red blue green yellow/a,
            player <- context.one_round do
          pass_on_company(player, company)
        end

      game = context.game
      game = handle_commands(game, commands)
      refute Enum.find(game.events, &String.contains?(&1.name, "reject"))

      # WHEN we emit another start_player_turn command
      command = Messages.start_player_turn(user: :game)
      game = handle_one_command(game, command)

      # THEN the command is rejected
      assert event = fetch_single_event!(game, "player_turn_rejected")
      assert event.payload == %{message: "A player's turn is already in progress"}
    end
  end

  #########################################################
  # Player Action Option #1A: Buy Single Stock
  #########################################################

  describe "purchase_single_stock -> single_stock_purchase_rejected" do
    @describetag :start_game

    test "when not a player turn (e.g. auction phase)", context do
      # GIVEN
      game = context.game
      refute Enum.find(game.events, &String.contains?(&1.name, "reject"))

      # WHEN
      wrong_player =
        context.one_round |> Enum.reject(&(&1 == context.start_player)) |> Enum.random()

      wrong_company = :black
      command = purchase_single_stock(wrong_player, wrong_company, @incorrect_price)
      game = handle_one_command(context.game, command)

      # THEN
      assert event = fetch_single_event!(game, "single_stock_purchase_rejected")

      assert event.payload == %{
               purchasing_player: wrong_player,
               company: wrong_company,
               price: @incorrect_price,
               reason: "not a player turn"
             }
    end

    test "when not a player turn (e.g. end-of-turn sequence)"

    @tag :random_first_auction_phase
    test "incorrect player (not start player)", context do
      # GIVEN
      correct_player = context.start_player
      assert [] = Enum.filter(context.game.events, &String.contains?(&1.name, "reject"))

      # WHEN
      wrong_player =
        context.one_round |> Enum.reject(&(&1 == correct_player)) |> Enum.random()

      wrong_company = :black
      command = purchase_single_stock(wrong_player, wrong_company, @incorrect_price)
      game = handle_one_command(context.game, command)

      # THEN
      assert event = fetch_single_event!(game, "single_stock_purchase_rejected")

      assert event.payload == %{
               purchasing_player: wrong_player,
               company: wrong_company,
               price: @incorrect_price,
               reason: "incorrect player"
             }
    end

    test "incorrect player (not second player)"

    test "company not active", context do
      # GIVEN
      # Only yellow gets auctioned off
      game = context.game
      start_player = context.start_player
      winning_bid = current_money(game, start_player)
      only_auctioned_company = :yellow

      game =
        [
          for company <- ~w/red blue green yellow/a,
              player <- context.one_round do
            if player == start_player and company == only_auctioned_company do
              submit_bid(start_player, only_auctioned_company, winning_bid)
            else
              pass_on_company(player, company)
            end
          end,
          build_rail_link(start_player, only_auctioned_company, ["moscow", "nizhnynovgorod"]),
          set_stock_value(start_player, only_auctioned_company, winning_bid)
        ]
        |> injest_commands(game)

      # WHEN
      attempted_company = :red
      command = purchase_single_stock(start_player, attempted_company, winning_bid)
      game = handle_one_command(game, command)

      # THEN
      assert event = fetch_single_event!(game, "single_stock_purchase_rejected")

      assert event.payload == %{
               purchasing_player: start_player,
               company: attempted_company,
               price: winning_bid,
               reason: "company was never active"
             }
    end

    test "insufficient funds", context do
      # GIVEN
      # Only one player (start player) wins an auction for all his money.
      # He then sets the starting stock price at the same amount.
      game = context.game
      start_player = context.start_player
      winning_bid = current_money(game, start_player)
      only_auctioned_company = :yellow

      commands =
        for company <- ~w/red blue green yellow/a,
            player <- context.one_round do
          if player == start_player and company == only_auctioned_company do
            submit_bid(start_player, only_auctioned_company, winning_bid)
          else
            pass_on_company(player, company)
          end
        end

      commands = [
        commands,
        build_rail_link(start_player, only_auctioned_company, ["moscow", "nizhnynovgorod"]),
        set_stock_value(start_player, only_auctioned_company, winning_bid)
      ]

      game = handle_commands(game, commands)

      # WHEN
      command = purchase_single_stock(start_player, only_auctioned_company, winning_bid)
      game = handle_one_command(game, command)

      # THEN
      assert event = fetch_single_event!(game, "single_stock_purchase_rejected")

      assert event.payload == %{
               purchasing_player: start_player,
               company: only_auctioned_company,
               price: winning_bid,
               reason: "insufficient funds"
             }
    end

    @tag start_player: 1
    @tag player_count: 3
    @tag player_order: [1, 2, 3]
    test "company stock already all sold off", context do
      # GIVEN
      game = context.game

      game =
        handle_commands(game, [
          for company <- ~w/red blue green yellow/a,
              player <- context.one_round do
            if player == 3 and company == :yellow do
              [
                submit_bid(player, company, 8),
                build_rail_link(player, company, ["moscow", "nizhnynovgorod"]),
                set_stock_value(player, company, 8)
              ]
            else
              pass_on_company(player, company)
            end
          end,
          purchase_single_stock(3, :yellow, 8),
          purchase_single_stock(1, :yellow, 8),
          purchase_single_stock(2, :yellow, 8),
          purchase_single_stock(3, :yellow, 8)
        ])

      assert 4 ==
               game.events
               |> Enum.filter(&String.contains?(&1.name, "single_stock_purchased"))
               |> Enum.count()

      assert [] == Enum.filter(game.events, &String.contains?(&1.name, "reject"))

      # WHEN
      # Now that all red stock have been auctioned and sold off, try to buy one more
      game = handle_one_command(game, purchase_single_stock(1, :yellow, 8))

      # THEN
      assert event = fetch_single_event!(game, "single_stock_purchase_rejected")

      assert event.payload == %{
               purchasing_player: 1,
               company: :yellow,
               price: 8,
               reason: "company has no stock to sell"
             }
    end

    test "company has been nationalized"

    @tag start_player: 1
    @tag player_count: 3
    @tag player_order: [1, 2, 3]
    test "does not match current stock price", context do
      # GIVEN
      game = context.game

      game =
        handle_commands(game, [
          for company <- ~w/red blue green yellow/a,
              player <- context.one_round do
            if player == 3 and company == :yellow do
              [
                submit_bid(player, company, 8),
                build_rail_link(player, company, ["moscow", "nizhnynovgorod"]),
                set_stock_value(player, company, 8)
              ]
            else
              pass_on_company(player, company)
            end
          end
        ])

      refute Enum.find(game.events, &String.contains?(&1.name, "reject"))

      # WHEN
      # Now that all red stock have been auctioned and sold off, try to buy one more
      command = purchase_single_stock(3, :yellow, 12)
      game = handle_one_command(game, command)

      # THEN
      assert event = fetch_single_event!(game, "single_stock_purchase_rejected")

      assert event.payload == %{
               purchasing_player: 3,
               company: :yellow,
               price: 12,
               reason: "does not match current stock price"
             }
    end
  end

  describe "purchase_single_stock -> single_stock_purchased" do
    @describetag start_player: 1
    @describetag player_count: 3
    @describetag player_order: [1, 2, 3]
    @describetag :start_game
    setup context do
      # GIVEN
      game = context.game

      game =
        handle_commands(game, [
          for company <- ~w/red blue green yellow/a,
              player <- context.one_round do
            if player == 3 and company == :yellow do
              [
                submit_bid(player, company, 8),
                build_rail_link(player, company, ["moscow", "nizhnynovgorod"]),
                set_stock_value(player, company, 8)
              ]
            else
              pass_on_company(player, company)
            end
          end
        ])

      # THEN
      refute Enum.find(game.events, &String.contains?(&1.name, "reject"))

      [game: game]
    end

    @purchase_single_stock purchase_single_stock(3, :yellow, 8)

    test "happy path", context do
      # GIVEN
      game = context.game
      refute get_latest_event(game, "single_stock_purchased")

      # WHEN
      game = handle_one_command(game, @purchase_single_stock)

      # THEN
      assert event = fetch_single_event!(game, "single_stock_purchased")
      assert event.payload == %{company: :yellow, price: 8, purchasing_player: 3}
    end

    test "-> money_transferred", context do
      # GIVEN
      game = context.game
      money_transferred_events = filter_events(game, "money_transferred")

      # WHEN
      game = handle_one_command(game, @purchase_single_stock)

      # THEN
      assert [event | ^money_transferred_events] =
               filter_events(game, "money_transferred")

      assert event.payload == %{
               transfers: %{3 => -8, :yellow => 8},
               reason: "single stock purchased"
             }
    end

    test "-> stock_transferred", context do
      # GIVEN
      game = context.game

      stock_transferred_events =
        filter_events(game, "stock_certificates_transferred")

      # WHEN
      game = handle_one_command(game, @purchase_single_stock)

      # THEN
      assert [event | ^stock_transferred_events] =
               filter_events(game, "stock_certificates_transferred")

      assert event.payload == %{
               company: :yellow,
               from: :yellow,
               to: 3,
               quantity: 1,
               reason: "single stock purchased"
             }
    end

    test "-> interturn_started", context do
      # GIVEN
      game = context.game
      refute get_latest_event(game, "interturn_started")

      # WHEN
      game = handle_one_command(game, @purchase_single_stock)

      # THEN
      assert event = fetch_single_event!(game, "interturn_skipped")
      assert event.payload == %{}
    end
  end

  #########################################################
  # Player Action Option #3: Pass
  #########################################################

  describe "pass_rejected when" do
    test "not a player turn (e.g. setup)" do
      # GIVEN
      game =
        init_and_add_players(3)
        |> handle_one_command(set_player_order([1, 2, 3]))

      # WHEN
      game = handle_one_command(game, pass(1))

      # THEN
      assert event = fetch_single_event!(game, "pass_rejected")
      assert event.payload.passing_player == 1
    end

    test "not a player turn (e.g. end-of-turn sequence)"

    @tag :start_game
    @tag :random_first_auction_phase
    test "incorrect player", context do
      # GIVEN
      correct_player = context.start_player
      assert [] = Enum.filter(context.game.events, &String.contains?(&1.name, "reject"))

      # WHEN
      wrong_player = context.one_round |> Enum.reject(&(&1 == correct_player)) |> Enum.random()
      game = handle_one_command(context.game, pass(wrong_player))

      # THEN
      assert event = fetch_single_event!(game, "pass_rejected")
      assert event.payload == %{passing_player: wrong_player, reason: "incorrect player"}
    end
  end

  describe "passed" do
    @tag :start_game
    @tag :random_first_auction_phase
    test "-> interturn_started", context do
      # GIVEN
      game = context.game
      refute Enum.find(game.events, &String.contains?(&1.name, "reject"))

      # WHEN
      game = handle_one_command(game, pass(context.start_player))

      # THEN
      assert fetch_single_event!(game, "passed")
      assert fetch_single_event!(game, "interturn_skipped")
    end
  end
end
