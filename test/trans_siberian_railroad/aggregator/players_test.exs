defmodule TransSiberianRailroad.PlayersTest do
  use ExUnit.Case
  import TransSiberianRailroad.GameTestHelpers
  alias TransSiberianRailroad.Aggregator.Players
  alias TransSiberianRailroad.Game
  alias TransSiberianRailroad.Messages
  alias TransSiberianRailroad.Player
  alias TransSiberianRailroad.Projection

  test "add_player -> player_added" do
    for player_count <- 1..5 do
      # ARRANGE
      commands = [Messages.initialize_game() | add_player_commands(player_count)]

      # ACT
      game = Game.handle_commands(commands)

      # ASSERT
      players = project(game.events)
      assert Players.count(players) == player_count
    end
  end

  # TODO test that player_rejected also happens before game init and after game start
  test "add_player -> player_rejected when game is already full" do
    # ARRANGE - add 5 players. Game is now full.
    game =
      [Messages.initialize_game() | add_player_commands(5)]
      |> Game.handle_commands()

    # ACT - attempt to add a 6th player
    game = Game.handle_one_command(game, Messages.add_player("Frank"))

    # ASSERT - there are still only 5 players and the 6th player was rejected
    players = project(game.events)
    assert Players.count(players) == 5
    assert event = fetch_single_event!(game.events, "player_rejected")
    assert event.payload.player_name == "Frank"
  end

  describe "players' starting money" do
    test "is zero prior to game_started" do
      # ARRANGE
      player_count = Enum.random(1..5)

      # ACT
      game =
        [Messages.initialize_game() | add_player_commands(player_count)]
        |> Game.handle_commands()

      # ASSERT
      for %Player{money: money} <- project(game.events) |> Players.to_list() do
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
          Messages.start_game()
        ]

        # ACT
        game = Game.handle_commands(commands)

        # ASSERT
        # TODO extact intermediate var
        players = project(game.events) |> Players.to_list()
        assert length(players) == player_count

        for %Player{money: money} <- project(game.events) |> Players.to_list() do
          assert money == expected_money
        end
      end
    end
  end

  # TODO I shouldn't be projecting and inspecting their internals
  defp project(events) do
    Projection.project(Players, events)
  end
end
