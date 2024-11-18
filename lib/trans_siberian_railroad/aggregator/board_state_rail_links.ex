defmodule TransSiberianRailroad.Aggregator.BoardState.RailLinks do
  @moduledoc """
  Tracks which rail links have been built and by which company.
  """

  use TransSiberianRailroad.Aggregator
  alias TransSiberianRailroad.RailLinks

  aggregator_typedstruct do
    field :built_rail_links, [{Constants.company(), RailLinks.rail_link()}]
  end

  handle_command "validate_rail_link_connection", ctx do
    %{company: company, rail_link: rail_link} = ctx.payload

    case RailLinks.fetch_rail_link_income(rail_link) do
      {:ok, _} ->
        &Messages.rail_link_connection_validated(company, rail_link, nil, &1)

      {:error, reason} ->
        &Messages.rail_link_connection_validated(company, rail_link, reason, &1)
    end
  end
end
