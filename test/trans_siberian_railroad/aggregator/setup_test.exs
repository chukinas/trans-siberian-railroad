defmodule TransSiberianRailroad.Aggregator.SetupTest do
  use ExUnit.Case, async: true
  import TransSiberianRailroad.CommandFactory
  import TransSiberianRailroad.GameHelpers
  import TransSiberianRailroad.GameTestHelpers

  taggable_setups()

  test "initialize_game -> game_initialized only if it's the first event"

  test "add_player -> player_added" do
    for player_count <- 1..5 do
      # GIVEN
      commands = [initialize_game() | add_player_commands(player_count)]

      # WHEN
      game = handle_commands(commands)

      # THEN
      events = filter_events(game, "player_added")
      assert length(events) == player_count
    end
  end

  describe "add_player -> player_rejected" do
    test "when already player_order_set" do
      # GIVEN
      game =
        handle_commands([
          initialize_game(),
          add_player_commands(3),
          set_player_order([1, 2, 3])
        ])

      # WHEN
      game = handle_one_command(game, add_player("David"))

      # THEN
      assert event = fetch_single_event!(game, "player_rejected")
      assert event.payload.player_name == "David"
    end

    test "when there are already 5 players" do
      # GIVEN - add 5 players. Game is now full.
      game = init_and_add_players(5)

      # WHEN - attempt to add a 6th player
      game = handle_one_command(game, add_player("Frank"))

      # THEN - there are still only 5 players and the 6th player was rejected
      assert event = fetch_single_event!(game, "player_rejected")
      assert event.payload.player_name == "Frank"
    end
  end

  test "initialize_game -> game_initialization_rejected when game already initialized" do
    # GIVEN
    game = handle_commands([initialize_game()])

    # WHEN
    game = handle_one_command(game, initialize_game())

    # THEN
    assert fetch_single_event!(game, "game_initialization_rejected")
  end

  test "set_start_player is an optional command" do
    # GIVEN
    player_count = Enum.random(3..5)
    start_player = Enum.random(1..player_count)

    commands =
      [
        initialize_game(),
        add_player_commands(player_count),
        set_start_player(start_player),
        start_game()
      ]

    # WHEN
    game = handle_commands(commands)

    # THEN
    assert fetch_single_event!(game, "start_player_set").payload.start_player ==
             start_player
  end

  test "set_start_player is rejected if game has already started"
  test "set_start_player is rejected if the player does not exist"

  test "set_player_order is an optional command" do
    # GIVEN
    player_count = Enum.random(3..5)
    player_order = Enum.shuffle(1..player_count)

    commands =
      [
        initialize_game(),
        add_player_commands(player_count),
        set_player_order(player_order),
        start_game()
      ]

    # WHEN
    game = handle_commands(commands)

    # THEN
    assert fetch_single_event!(game, "player_order_set").payload.player_order ==
             player_order
  end

  @tag :start_game
  test "game_started -> auction_phase_started", context do
    # GIVEN/WHEN: see :start_game setup
    game = context.game
    assert fetch_single_event!(game, "game_started")

    # THEN
    assert fetch_single_event!(game, "auction_phase_started")
  end

  test "the player who won the last stock in the initial auction is the start player"
  test "player and company balances may never be negative"
  test "all events have incrementing sequence numbers"

  describe "players' starting money" do
    test "is zero prior to game_started" do
      # GIVEN
      player_count = Enum.random(1..5)

      # WHEN
      game = init_and_add_players(player_count)

      # THEN
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
        # GIVEN
        game = init_and_add_players(player_count)

        # WHEN
        game = handle_one_command(game, start_game())

        # THEN
        for player_id <- 1..player_count do
          assert current_money(game, player_id) == expected_money
        end
      end
    end
  end
end
