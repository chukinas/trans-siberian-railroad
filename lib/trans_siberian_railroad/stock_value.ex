defmodule TransSiberianRailroad.StockValue do
  @moduledoc """
  Every public rail company has a stock value.
  This is how much it costs to buy a share of that company.
  In Phase 2 of the game, railroads whose stock value is below "Nationalization Value"
  will be nationalized (bought out by the government).
  """

  @max_value 75
  @stock_value_spaces [8..48//4, 50..70//2, [@max_value]]
                      |> Enum.map(&Enum.to_list/1)
                      |> List.flatten()

  @type t() :: pos_integer()

  # Instead of writing a test, check this at compile time.
  # Otherwise I would have had to have written a public function.
  23 = Enum.count(@stock_value_spaces)

  @doc """
  When a company's first stock is purchased (always at a minimum of 8 money),
  That player sets the initial stock value (less than or equal to bid).
  """
  def available_initial_stock_values(bid) when is_integer(bid) and bid >= 8 do
    Enum.filter(@stock_value_spaces, &(&1 <= bid))
  end

  def increase(starting_stock_value, count_spaces)
      when starting_stock_value in @stock_value_spaces and is_integer(count_spaces) and
             count_spaces >= 0 do
    @stock_value_spaces
    |> Enum.reject(&(&1 < starting_stock_value))
    |> Enum.drop(count_spaces)
    |> case do
      [new_value | _] -> new_value
      [] -> @max_value
    end
  end

  def causes_game_end?(stock_value), do: stock_value == @max_value
end
