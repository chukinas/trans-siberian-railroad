defmodule TransSiberianRailroad.Players do
  @moduledoc """
  Currently, just provides a helper for simplifying a common task:
  given the player order and a start player, return the a list of players
  in player order beginning with that start player.
  """

  def one_round(player_order, start_player) do
    player_count = length(player_order)

    player_order
    |> Stream.cycle()
    |> Stream.drop_while(&(&1 != start_player))
    |> Enum.take(player_count)
  end

  def next_player(player_order, current_player) do
    player_order
    |> one_round(current_player)
    |> Enum.drop(1)
    |> hd()
  end

  def previous_player(player_order, current_player) do
    player_order
    |> one_round(current_player)
    |> Enum.at(-1)
  end
end
