defmodule TransSiberianRailroad.Constants do
  #########################################################
  # Players
  #########################################################

  @type player() :: 1..5
  defguard is_player(x) when x in 1..5

  #########################################################
  # Companies
  #########################################################

  @type company() :: :red | :blue | :green | :yellow | :black | :white
  @companies ~w(red blue green yellow black white)a
  def companies(), do: @companies
  defguard is_company(id) when id in @companies
end
