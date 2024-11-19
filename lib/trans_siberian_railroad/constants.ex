defmodule TransSiberianRailroad.Constants do
  #########################################################
  # Players
  #########################################################

  @type player() :: 1..5
  defguard is_player(x) when x in 1..5

  #########################################################
  # Companies
  #########################################################

  @type company() :: String.t()
  @companies ~w(red blue green yellow black white)
  def companies(), do: @companies
  defguard is_company(id) when id in @companies
end
