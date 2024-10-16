defmodule TransSiberianRailroad.Aggregator.MainTest do
  use ExUnit.Case
  import TransSiberianRailroad.GameTestHelpers
  alias TransSiberianRailroad.Banana
  alias TransSiberianRailroad.Messages

  test "initialize_game -> game_initialized only if it's the first event"
  test "initialize_game -> game_initialization_rejected when game already initialized"

  test "set_start_player is an optional command" do
    # ARRANGE
    player_count = Enum.random(3..5)
    start_player = Enum.random(1..player_count)
    player_who_requested_game_start = Enum.random(1..player_count)

    commands =
      [
        Messages.initialize_game(),
        add_player_commands(player_count),
        Messages.set_start_player(start_player),
        Messages.start_game(player_who_requested_game_start)
      ]

    # ACT
    game = Banana.handle_commands(commands)

    # ASSERT
    assert fetch_single_event!(game.events, "start_player_selected").payload.start_player ==
             start_player
  end

  test "set_start_player is rejected if game has already started"
  test "set_start_player is rejected if the player does not exist"

  test "set_player_order is an optional command" do
    # ARRANGE
    player_count = Enum.random(3..5)
    player_order = Enum.shuffle(1..player_count)
    player_who_requested_game_start = Enum.random(1..player_count)

    commands =
      [
        Messages.initialize_game(),
        add_player_commands(player_count),
        Messages.set_player_order(player_order),
        Messages.start_game(player_who_requested_game_start)
      ]

    # ACT
    game = Banana.handle_commands(commands)

    # ASSERT
    assert fetch_single_event!(game.events, "player_order_set").payload.player_order ==
             player_order
  end
end
