defmodule Tsr.Income do
  @moduledoc """
  Rail Companies move up the income track whenever they lay track.
  Periodically, doing so causes their stock value to increase
  """

  @income_spaces 2..70
  @stock_value_increase_spaces [10, 15, 20, 26, 32, 38, 44, 51, 59, 66, 70]

  @typedoc """
  Any one of the #{inspect(@income_spaces)} spaces on the income track
  """
  @type t() :: pos_integer()

  def count_stock_value_increases(starting_income, final_income)
      when starting_income in @income_spaces and final_income in @income_spaces and
             starting_income <= final_income do
    @stock_value_increase_spaces
    |> Enum.filter(&(&1 in (starting_income + 1)..final_income))
    |> Enum.count()
  end
end
