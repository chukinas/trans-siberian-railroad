defmodule TransSiberianRailroad.PlayersTest do
  use ExUnit.Case
  import TransSiberianRailroad.GameTestHelpers
  alias TransSiberianRailroad.Aggregator.Players
  alias TransSiberianRailroad.Banana
  alias TransSiberianRailroad.Messages
  alias TransSiberianRailroad.Player

  test "add_player -> player_added" do
    for player_count <- 1..5 do
      # ARRANGE
      commands = [Messages.initialize_game() | add_player_commands(player_count)]

      # ACT
      game = Banana.handle_commands(commands)

      # ASSERT
      players = Players.project(game.events)
      assert Players.count(players) == player_count
    end
  end

  # TODO test that player_rejected also happens before game init and after game start
  test "add_player -> player_rejected when game is already full" do
    # ARRANGE - add 5 players. Game is now full.
    game =
      [Messages.initialize_game() | add_player_commands(5)]
      |> Banana.handle_commands()

    # ACT - attempt to add a 6th player
    game = Banana.handle_command(game, Messages.add_player("Frank"))

    # ASSERT - there are still only 5 players and the 6th player was rejected
    players = Players.project(game.events)
    assert Players.count(players) == 5
    assert Banana.get_last_event(game).name == "player_rejected"
  end

  describe "players' starting money" do
    test "is zero prior to game_started" do
      # ARRANGE
      player_count = Enum.random(1..5)

      # ACT
      game =
        [Messages.initialize_game() | add_player_commands(player_count)]
        |> Banana.handle_commands()

      # ASSERT
      for %Player{money: money} <- Players.project(game.events) do
        assert money == 0
      end
    end

    test "is available after game_started" do
      for {player_count, expected_money} <- [
            {3, 48},
            {4, 40},
            {5, 32}
          ] do
        # ARRANGE
        commands = [
          Messages.initialize_game(),
          add_player_commands(player_count),
          Messages.start_game(Enum.random(1..player_count))
        ]

        # ACT
        game = Banana.handle_commands(commands)

        # ASSERT
        players = Players.project(game.events)
        assert Players.count(players) == player_count

        for %Player{money: money} <- Players.project(game.events) do
          assert money == expected_money
        end
      end
    end
  end
end
