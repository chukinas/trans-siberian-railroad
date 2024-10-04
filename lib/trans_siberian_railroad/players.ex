defmodule TransSiberianRailroad.Players do
  alias TransSiberianRailroad.Player
  @type t() :: [Player.t()]

  @spec new() :: t()
  def new(), do: []

  @spec add(t(), Player.id(), String.t()) :: t()
  def add(players, player_id, player_name) do
    added_player = Player.new(player_id, player_name)
    [added_player | players]
  end

  def set_starting_money(players, amount) do
    for %Player{} = player <- players do
      %Player{player | money: amount}
    end
  end

  #########################################################
  # HELPERS
  #########################################################

  def starting_money(player_count)
  def starting_money(3), do: 48
  def starting_money(4), do: 40
  def starting_money(5), do: 32
end
