defmodule TransSiberianRailroad.GameTestHelpers do
  alias TransSiberianRailroad.Game
  alias TransSiberianRailroad.Messages

  #########################################################
  # Game
  #########################################################

  def game_from_commands(commands) do
    Enum.reduce(commands, Game.new(), &Game.handle_command(&2, &1))
  end

  def handle_commands(game, commands) do
    Enum.reduce(commands, game, &Game.handle_command(&2, &1))
  end

  def game_has_event?(game, event_name) do
    Enum.any?(game.events, fn event -> event.name == event_name end)
  end

  #########################################################
  # Commands
  #########################################################

  def add_player_commands(player_count) when player_count in 1..6 do
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
end
