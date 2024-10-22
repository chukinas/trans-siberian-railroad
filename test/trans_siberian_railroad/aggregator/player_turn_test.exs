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

  #########################################################
  # Player Action Option #1A: Buy Single Stock
  #########################################################

  describe "purchase_single_stock -> single_stock_purchase_rejected" do
    @tag :start_game
    test "when not a player turn (e.g. auction phase)", context do
      # ARRANGE
      game = context.game
      refute Enum.find(game.events, &String.contains?(&1.name, "reject"))

      # ACT
      # TODO I think I like the wording "wrong player" and "wrong company" better?
      incorrect_player =
        context.one_round |> Enum.reject(&(&1 == context.start_player)) |> Enum.random()

      incorrect_company = :black
      incorrect_price = 76

      game =
        Game.handle_one_command(
          game,
          Messages.purchase_single_stock(incorrect_player, incorrect_company, incorrect_price)
        )

      # ASSERT
      assert event = fetch_single_event!(game.events, "single_stock_purchase_rejected")

      assert event.payload == %{
               purchasing_player: incorrect_player,
               company: incorrect_company,
               price: incorrect_price,
               reason: "not a player turn"
             }
    end

    test "when not a player turn (e.g. end-of-turn sequence)"
    test "incorrect player"
    test "insufficient funds"
    test "company not active"
    test "company stock already all sold off"
    test "company has been nationalized"
    test "incorrect price"
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
