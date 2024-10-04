defmodule TransSiberianRailroad.GameTest do
  use ExUnit.Case
  alias TransSiberianRailroad.Auction
  alias TransSiberianRailroad.Event
  alias TransSiberianRailroad.Game
  alias TransSiberianRailroad.Messages
  alias TransSiberianRailroad.Player

  test "reject player when game is full" do
    commands = [Messages.initialize_game() | add_player_commands(5)]
    game = game_from_commands(commands)
    assert length(game.snapshot.players) == 5

    # Now we will try but fail to add a sixth player
    commands = [Messages.add_player("Frank")]
    game = handle_commands(game, commands)
    assert length(game.snapshot.players) == 5
    assert [%Event{name: "player_rejected"} | _] = game.events
  end

  defp add_player_commands(player_count) when player_count in 1..6 do
    [
      Messages.add_player("Alice"),
      Messages.add_player("Bob"),
      Messages.add_player("Charlie"),
      Messages.add_player("David"),
      Messages.add_player("Eve"),
      Messages.add_player("Frank")
    ]
    |> Enum.take(player_count)
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

        for %Player{money: money} <- game.snapshot.players do
          assert money == expected_money
        end
      end
    end
  end

  describe "first auction" do
    setup do
      player_count = Enum.random(3..5)

      start_game_commands =
        List.flatten([
          Messages.initialize_game(),
          add_player_commands(player_count),
          Messages.start_game(Enum.random(1..player_count))
        ])

      [started_game: game_from_commands(start_game_commands)]
    end

    test "A started game also has an auction_started event", %{started_game: game} do
      assert game_has_event?(game, "game_started")

      case Enum.filter(game.events, &(&1.name == "auction_started")) do
        [%Event{payload: payload}] ->
          assert Auction.current_bidder!(game.auction) == payload.current_bidder
      end

      assert Auction.in_progress?(game.auction)
    end
  end

  defp game_from_commands(commands) do
    Enum.reduce(commands, Game.new(), &Game.handle_command(&2, &1))
  end

  defp handle_commands(game, commands) do
    Enum.reduce(commands, game, &Game.handle_command(&2, &1))
  end

  defp game_has_event?(game, event_name) do
    Enum.any?(game.events, fn event -> event.name == event_name end)
  end
end
