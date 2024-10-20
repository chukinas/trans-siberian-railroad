defmodule TransSiberianRailroad.Aggregator.MainTest do
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

  describe "initialize_game -> game_initialization_rejected" do
    # TODO when else
    test "when game already initialized"
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
end
