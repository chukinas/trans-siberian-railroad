defmodule TransSiberianRailroad.Aggregator.PlayerTurnTest do
  use ExUnit.Case
  import TransSiberianRailroad.GameTestHelpers
  alias TransSiberianRailroad.Game
  alias TransSiberianRailroad.Messages

  # TODO this is repeated from auction_test.exs
  setup context do
    if context[:start_game],
      do: start_game(context),
      else: :ok
  end

  setup context do
    if context[:auction_off_company],
      do: auction_off_company(context),
      else: :ok
  end

  # TODO there has to be a better way of doing this
  setup context do
    if context[:random_first_auction_phase],
      do: random_first_auction_phase(context),
      else: :ok
  end

  @incorrect_price 76

  #########################################################
  # Player Action Option #1A: Buy Single Stock
  #########################################################

  describe "purchase_single_stock -> single_stock_purchase_rejected" do
    @describetag :start_game

    test "when not a player turn (e.g. auction phase)", context do
      # ARRANGE
      game = context.game
      refute Enum.find(game.events, &String.contains?(&1.name, "reject"))

      # ACT
      # TODO I think I like the wording "wrong player" and "wrong company" better?
      # TODO extract function
      incorrect_player =
        context.one_round |> Enum.reject(&(&1 == context.start_player)) |> Enum.random()

      incorrect_company = :black

      command =
        Messages.purchase_single_stock(incorrect_player, incorrect_company, @incorrect_price)

      game = Game.handle_one_command(context.game, command)

      # ASSERT
      assert event = fetch_single_event!(game.events, "single_stock_purchase_rejected")

      assert event.payload == %{
               purchasing_player: incorrect_player,
               company: incorrect_company,
               price: @incorrect_price,
               reason: "not a player turn"
             }
    end

    test "when not a player turn (e.g. end-of-turn sequence)"

    @tag :random_first_auction_phase
    test "incorrect player (not start player)", context do
      # ARRANGE
      correct_player = context.start_player
      assert [] = Enum.filter(context.game.events, &String.contains?(&1.name, "reject"))

      # ACT
      incorrect_player =
        context.one_round |> Enum.reject(&(&1 == correct_player)) |> Enum.random()

      incorrect_company = :black

      command =
        Messages.purchase_single_stock(incorrect_player, incorrect_company, @incorrect_price)

      game = Game.handle_one_command(context.game, command)

      # ASSERT
      assert event = fetch_single_event!(game.events, "single_stock_purchase_rejected")

      assert event.payload == %{
               purchasing_player: incorrect_player,
               company: incorrect_company,
               price: @incorrect_price,
               reason: "incorrect player"
             }
    end

    test "incorrect player (not second player)"

    test "company not active", context do
      # ARRANGE
      # Only yellow gets auctioned off
      game = context.game
      start_player = context.start_player
      winning_bid = current_money(game, start_player)
      only_auctioned_company = :yellow

      commands =
        for company <- ~w/red blue green yellow/a,
            player <- context.one_round do
          if player == start_player and company == only_auctioned_company do
            Messages.submit_bid(start_player, only_auctioned_company, winning_bid)
          else
            Messages.pass_on_company(player, company)
          end
        end

      commands = [
        commands,
        Messages.set_starting_stock_price(start_player, only_auctioned_company, winning_bid)
      ]

      game = Game.handle_commands(game, commands)

      # ACT
      attempted_company = :red
      command = Messages.purchase_single_stock(start_player, attempted_company, winning_bid)
      game = Game.handle_one_command(game, command)

      # ASSERT
      assert event = fetch_single_event!(game.events, "single_stock_purchase_rejected")

      assert event.payload == %{
               purchasing_player: start_player,
               company: attempted_company,
               price: winning_bid,
               reason: "company was never active"
             }
    end

    test "insufficient funds", context do
      # ARRANGE
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
            Messages.submit_bid(start_player, only_auctioned_company, winning_bid)
          else
            Messages.pass_on_company(player, company)
          end
        end

      commands = [
        commands,
        Messages.set_starting_stock_price(start_player, only_auctioned_company, winning_bid)
      ]

      game = Game.handle_commands(game, commands)

      # ACT
      command = Messages.purchase_single_stock(start_player, only_auctioned_company, winning_bid)
      game = Game.handle_one_command(game, command)

      # ASSERT
      assert event = fetch_single_event!(game.events, "single_stock_purchase_rejected")

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
      # ARRANGE
      game =
        Game.handle_commands(context.game, [
          for company <- ~w/red blue green yellow/a,
              player <- context.one_round do
            if player == 3 and company == :yellow do
              [
                Messages.submit_bid(player, company, 8),
                Messages.set_starting_stock_price(player, company, 8)
              ]
            else
              Messages.pass_on_company(player, company)
            end
          end,
          Messages.purchase_single_stock(3, :yellow, 8),
          Messages.purchase_single_stock(1, :yellow, 8),
          Messages.purchase_single_stock(2, :yellow, 8),
          Messages.purchase_single_stock(3, :yellow, 8)
        ])

      refute Enum.find(game.events, &String.contains?(&1.name, "reject"))

      # ACT
      # Now that all red stock have been auctioned and sold off, try to buy one more
      game = Game.handle_one_command(game, Messages.purchase_single_stock(1, :yellow, 8))

      # ASSERT
      assert event = fetch_single_event!(game.events, "single_stock_purchase_rejected")

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
      # ARRANGE
      game =
        Game.handle_commands(context.game, [
          for company <- ~w/red blue green yellow/a,
              player <- context.one_round do
            if player == 3 and company == :yellow do
              [
                Messages.submit_bid(player, company, 8),
                Messages.set_starting_stock_price(player, company, 8)
              ]
            else
              Messages.pass_on_company(player, company)
            end
          end
        ])

      refute Enum.find(game.events, &String.contains?(&1.name, "reject"))

      # ACT
      # Now that all red stock have been auctioned and sold off, try to buy one more
      command = Messages.purchase_single_stock(3, :yellow, 12)
      game = Game.handle_one_command(game, command)

      # ASSERT
      assert event = fetch_single_event!(game.events, "single_stock_purchase_rejected")

      assert event.payload == %{
               purchasing_player: 3,
               company: :yellow,
               price: 12,
               reason: "does not match current stock price"
             }
    end
  end

  describe "purchase_single_stock -> single_stock_purchased" do
    test "-> money_transferred"
    test "-> stock_transferred"
    test "-> end_of_turn_sequence_started"
  end

  #########################################################
  # Player Action Option #3: Pass
  #########################################################

  # TODO follow the naming conventions above
  describe "pass_rejected when" do
    test "not a player turn (e.g. setup)" do
      # ARRANGE
      game =
        Game.handle_commands([
          Messages.initialize_game(),
          add_player_commands(3),
          Messages.set_player_order([1, 2, 3])
        ])

      # ACT
      game = Game.handle_one_command(game, Messages.pass(1))

      # ASSERT
      assert event = fetch_single_event!(game.events, "pass_rejected")
      assert event.payload.passing_player == 1
    end

    test "not a player turn (e.g. end-of-turn sequence)"

    @tag :start_game
    @tag :random_first_auction_phase
    test "incorrect player", context do
      # ARRANGE
      correct_player = context.start_player
      assert [] = Enum.filter(context.game.events, &String.contains?(&1.name, "reject"))

      # ACT
      incorrect_player =
        context.one_round |> Enum.reject(&(&1 == correct_player)) |> Enum.random()

      game = Game.handle_one_command(context.game, Messages.pass(incorrect_player))

      # ASSERT
      assert event = fetch_single_event!(game.events, "pass_rejected")
      assert event.payload == %{passing_player: incorrect_player, reason: "incorrect player"}
    end
  end

  describe "passed" do
    @tag :start_game
    @tag :random_first_auction_phase
    test "-> end_of_turn_sequence_started", context do
      # ARRANGE
      game = context.game
      refute Enum.find(game.events, &String.contains?(&1.name, "reject"))

      # ACT
      game = Game.handle_one_command(game, Messages.pass(context.start_player))

      # ASSERT
      assert fetch_single_event!(game.events, "passed")
      assert fetch_single_event!(game.events, "end_of_turn_sequence_started")
    end
  end
end
