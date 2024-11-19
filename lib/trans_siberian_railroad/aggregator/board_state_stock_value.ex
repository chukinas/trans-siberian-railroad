defmodule TransSiberianRailroad.Aggregator.BoardState.StockValue do
  @moduledoc """
  Track the value of stock certificates.

  Every public rail company has a stock value.
  This is how much it costs to buy a share of that company.
  In Phase 2 of the game, railroads whose stock value is below "Nationalization Value"
  will be nationalized (bought out by the government).
  At the end of the game, players receive this value for each stock they own.

  Stock value dictates
  - The rubles a player must pay to buy a stock certificate
  - When a company gets nationalized,
    the tsar buys out the owner of each stock certificate at the current stock value
  - During Interturn, the company with the highest stock value has its stock value increased by 1.
  """

  use TransSiberianRailroad.Aggregator

  aggregator_typedstruct do
    field :stock_values, %{Constants.company() => non_neg_integer()}, default: %{}
    field :do_game_end_stock_values, boolean(), default: false
  end

  ########################################################
  # constants
  ########################################################

  @max_value 75
  @stock_value_spaces [8..48//4, 50..70//2, [@max_value]]
                      |> Enum.map(&Enum.to_list/1)
                      |> List.flatten()

  # Instead of writing a test, check this at compile time.
  # Otherwise I would have had to have written a public function.
  23 = Enum.count(@stock_value_spaces)

  def stock_value_spaces(), do: @stock_value_spaces

  ########################################################
  # track :stock_value
  ########################################################

  handle_event "stock_value_set", ctx do
    %{company: company, stock_value: stock_value} = ctx.payload
    [stock_values: Map.put(ctx.projection.stock_values, company, stock_value)]
  end

  handle_event "stock_value_incremented", ctx do
    %{company: company} = ctx.payload
    [stock_values: Map.update(ctx.projection.stock_values, company, 8, &increase(&1, 1))]
  end

  defp increase(starting_stock_value, count_spaces)
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

  handle_event "company_nationalized", ctx do
    %{company: company} = ctx.payload
    [stock_values: Map.delete(ctx.projection.stock_values, company)]
  end

  ########################################################
  # Messages.game_end_stock_values_determined
  ########################################################

  handle_event "game_end_sequence_started", _ctx do
    [do_game_end_stock_values: true]
  end

  defreaction maybe_game_end_stock_values_determined(%{projection: projection}) do
    if projection.do_game_end_stock_values do
      stock_values = projection.stock_values

      companies =
        Constants.companies()
        |> Enum.flat_map(
          &case stock_values[&1] do
            nil -> []
            value -> [%{company: &1, stock_value: value}]
          end
        )

      note =
        "this takes nationalization into account but ignores the effect of private companies, " <>
          "the value of whose stock certificates is actually zero at game end"

      event_builder("game_end_stock_values_determined",
        company_stock_values: companies,
        note: note
      )
    end
  end

  handle_event "game_end_stock_values_determined", _ctx do
    [do_game_end_stock_values: false]
  end
end
