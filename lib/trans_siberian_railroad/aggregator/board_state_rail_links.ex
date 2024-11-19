defmodule TransSiberianRailroad.Aggregator.BoardState.RailLinks do
  @moduledoc """
  Tracks which rail links have been built and by which company.
  """

  use TransSiberianRailroad.Aggregator
  alias TransSiberianRailroad.RailLinks

  aggregator_typedstruct do
    field :built_rail_links, [{Constants.company(), RailLinks.rail_link()}], default: []
  end

  #########################################################
  # Handle built links
  #########################################################

  handle_event "initial_rail_link_built", ctx do
    %{company: company, rail_link: rail_link} = ctx.payload
    [built_rail_links: [{company, rail_link} | ctx.projection.built_rail_links]]
  end

  handle_event "internal_rail_link_built", ctx do
    %{company: company, rail_link: rail_link} = ctx.payload
    [built_rail_links: [{company, rail_link} | ctx.projection.built_rail_links]]
  end

  #########################################################
  # Validate new links
  #########################################################

  handle_command "validate_company_rail_link", ctx do
    %{company: company, rail_link: rail_link} = ctx.payload

    maybe_error =
      with :ok <- validate_rail_link_exists(rail_link),
           :ok <- validate_rail_link_unbuilt(ctx.projection, rail_link),
           :ok <- validate_rail_link_connected(ctx.projection, company, rail_link) do
        nil
      else
        {:error, error} -> error
      end

    Messages.event_builder("company_rail_link_validated", %{
      company: company,
      rail_link: rail_link,
      maybe_error: maybe_error
    })
  end

  #########################################################
  # Converters
  #########################################################

  defp stream_company_cities(projection, company) do
    stream_company_rail_links(projection, company)
    |> Stream.flat_map(&elem(&1, 1))
    |> Stream.uniq()
  end

  defp stream_company_rail_links(projection, company) do
    Stream.filter(projection.built_rail_links, fn {built_company, _} ->
      built_company == company
    end)
  end

  defp validate_rail_link_connected(projection, company, rail_link) do
    if stream_company_cities(projection, company) |> Enum.find(&(&1 in rail_link)) do
      :ok
    else
      {:error, "rail link not connected to company's built rail links"}
    end
  end

  defp validate_rail_link_exists(rail_link) do
    case RailLinks.fetch_rail_link_income(rail_link) do
      {:ok, _} -> :ok
      {:error, error} -> {:error, error}
    end
  end

  defp validate_rail_link_unbuilt(projection, rail_link) do
    if Enum.any?(projection.built_rail_links, fn {_, built_rail_link} ->
         built_rail_link == rail_link
       end) do
      {:error, "rail link already built"}
    else
      :ok
    end
  end
end
