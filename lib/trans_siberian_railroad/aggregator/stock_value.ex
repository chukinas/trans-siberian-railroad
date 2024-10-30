defmodule TransSiberianRailroad.Aggregator.StockValue do
  @moduledoc """
  Each company (if it's sold any stock certificates and if it's not nationalized)
  tracks its stock value here.
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
