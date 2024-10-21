defmodule TransSiberianRailroad.Aggregator.SetupTest do
  use ExUnit.Case
  import TransSiberianRailroad.GameTestHelpers
  alias TransSiberianRailroad.Game
  alias TransSiberianRailroad.Messages

  setup context do
    if context[:start_game],
      do: start_game(context),
      else: :ok
  end

  test "initialize_game -> game_initialized only if it's the first event"

  test "add_player -> player_added" do
    for player_count <- 1..5 do
      # ARRANGE
      commands = [Messages.initialize_game() | add_player_commands(player_count)]

      # ACT
      game = Game.handle_commands(commands)

      # ASSERT
      events = filter_events_by_name(game.events, "player_added")
      assert length(events) == player_count
    end
  end

  describe "add_player -> player_rejected" do
    test "when already player_order_set" do
      # ARRANGE
      game =
        Game.handle_commands([
          Messages.initialize_game(),
          add_player_commands(3),
          Messages.set_player_order([1, 2, 3])
        ])

      # ACT
      game = Game.handle_one_command(game, Messages.add_player("David"))

      # ASSERT
      assert event = fetch_single_event!(game.events, "player_rejected")
      assert event.payload.player_name == "David"
    end

    test "when there are already 5 players" do
      # ARRANGE - add 5 players. Game is now full.
      commands = [Messages.initialize_game() | add_player_commands(5)]
      game = Game.handle_commands(commands)

      # ACT - attempt to add a 6th player
      game = Game.handle_one_command(game, Messages.add_player("Frank"))

      # ASSERT - there are still only 5 players and the 6th player was rejected
      assert event = fetch_single_event!(game.events, "player_rejected")
      assert event.payload.player_name == "Frank"
    end
  end

  test "initialize_game -> game_initialization_rejected when game already initialized" do
    # ARRANGE
    game = Game.handle_commands([Messages.initialize_game()])

    # ACT
    game = Game.handle_one_command(game, Messages.initialize_game())

    # ASSERT
    assert fetch_single_event!(game.events, "game_initialization_rejected")
  end

  test "set_start_player is an optional command" do
    # ARRANGE
    player_count = Enum.random(3..5)
    start_player = Enum.random(1..player_count)

    commands =
      [
        Messages.initialize_game(),
        add_player_commands(player_count),
        Messages.set_start_player(start_player),
        Messages.start_game()
      ]

    # ACT
    game = Game.handle_commands(commands)

    # ASSERT
    assert fetch_single_event!(game.events, "start_player_set").payload.start_player ==
             start_player
  end

  test "set_start_player is rejected if game has already started"
  test "set_start_player is rejected if the player does not exist"

  test "set_player_order is an optional command" do
    # ARRANGE
    player_count = Enum.random(3..5)
    player_order = Enum.shuffle(1..player_count)

    commands =
      [
        Messages.initialize_game(),
        add_player_commands(player_count),
        Messages.set_player_order(player_order),
        Messages.start_game()
      ]

    # ACT
    game = Game.handle_commands(commands)

    # ASSERT
    assert fetch_single_event!(game.events, "player_order_set").payload.player_order ==
             player_order
  end

  @tag :start_game
  test "game_started -> auction_phase_started", context do
    # ARRANGE/ACT: see :start_game setup
    events = context.game.events
    assert fetch_single_event!(events, "game_started")

    # ASSERT
    assert fetch_single_event!(events, "auction_phase_started")
  end

  test "the player who won the last stock in the initial auction is the start player"
  test "player and company balances may never be negative"
  test "all events have incrementing sequence numbers"

  describe "players' starting money" do
    test "is zero prior to game_started" do
      # ARRANGE
      player_count = Enum.random(1..5)

      # ACT
      game =
        [Messages.initialize_game() | add_player_commands(player_count)]
        |> Game.handle_commands()

      # ASSERT
      for player_id <- 1..player_count do
        assert current_money(game, player_id) == 0
      end
    end

    test "is available after game_started" do
      for {player_count, expected_money} <- [
            {3, 48},
            {4, 40},
            {5, 32}
          ] do
        # ARRANGE
        commands = [Messages.initialize_game(), add_player_commands(player_count)]
        game = Game.handle_commands(commands)

        # ACT
        game = Game.handle_one_command(game, Messages.start_game())

        # ASSERT
        for player_id <- 1..player_count do
          assert current_money(game, player_id) == expected_money
        end
      end
    end
  end
end
