defmodule TransSiberianRailroad.Aggregator.StockValue do
  @moduledoc """
  Track the value of stock certificates.

  Stock value dictates
  - The price a player must pay to buy a stock certificate
  - When a company gets nationalized,
    the tsar buys out the owner of each stock certificate at the current stock value
  - During Interturn, the company with the highest stock value has its stock value increased by 1.
  """

  use TransSiberianRailroad.Aggregator
  use TransSiberianRailroad.Projection
  alias TransSiberianRailroad.Company
  alias TransSiberianRailroad.StockValue, as: StockValueCore

  aggregator_typedstruct do
    field :stock_values, %{Company.id() => non_neg_integer()}, default: %{}
  end

  handle_event "stock_value_set", ctx do
    %{company: company, value: value} = ctx.payload
    [stock_values: Map.put(ctx.projection.stock_values, company, value)]
  end

  handle_event "stock_value_incremented", ctx do
    %{company: company} = ctx.payload

    [
      stock_values:
        Map.update(ctx.projection.stock_values, company, 8, &StockValueCore.increase(&1, 1))
    ]
  end
end
