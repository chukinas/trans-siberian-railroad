defmodule TransSiberianRailroad.GameTest do
  use ExUnit.Case
  import TransSiberianRailroad.GameTestHelpers
  alias TransSiberianRailroad.Aggregator.Players
  alias TransSiberianRailroad.Event
  alias TransSiberianRailroad.Messages
  alias TransSiberianRailroad.Player

  test "reject player when game is full" do
    commands = [Messages.initialize_game() | add_player_commands(5)]
    game = game_from_commands(commands)
    assert Players.state(game.events) |> Players.count() == 5

    # Now we will try but fail to add a sixth player
    commands = [Messages.add_player("Frank")]
    game = handle_commands(game, commands)
    assert Players.state(game.events) |> Players.count() == 5
    assert [%Event{name: "player_rejected"} | _] = game.events
  end

  describe "starting money" do
    test "is zero prior to game_started" do
      player_count = Enum.random(3..5)
      commands = [Messages.initialize_game() | add_player_commands(player_count)]
      game = game_from_commands(commands)

      for %Player{money: money} <- game.snapshot.players do
        assert money == 0
      end
    end

    test "is in effect after game_started" do
      for {player_count, expected_money} <- [
            {3, 48},
            {4, 40},
            {5, 32}
          ] do
        commands =
          List.flatten([
            Messages.initialize_game(),
            add_player_commands(player_count),
            Messages.start_game(Enum.random(1..player_count))
          ])

        game = game_from_commands(commands)

        for %Player{money: money} <- Players.state(game.events) |> Players.to_list() do
          assert money == expected_money
        end
      end
    end
  end
end
