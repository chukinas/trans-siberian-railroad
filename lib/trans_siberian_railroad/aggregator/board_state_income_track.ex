defmodule Tsr.Aggregator.BoardState.IncomeTrack do
  @moduledoc """
  Tracks the income of each company and pays out dividends
  (`company_dividends_paid` and `dividends_paid`) in response to a `pay_dividends` command.
  """
  use Tsr.Aggregator
  alias Tsr.Income

  aggregator_typedstruct do
    plugin Tsr.Reactions
    field :company_incomes, %{Constants.company() => Income.t()}, default: %{}

    field :next_dividends_companies,
          [
            {
              event_uuid :: Ecto.UUID.t(),
              Constants.company(),
              income :: pos_integer()
            }
          ]
  end

  handle_command "pay_dividends", _ctx do
    event_builder("dividends_sequence_started")
  end

  handle_event "dividends_sequence_started", ctx do
    company_incomes = ctx.projection.company_incomes

    next_dividends_companies =
      Enum.flat_map(
        Constants.companies(),
        &case company_incomes[&1] do
          income when is_integer(income) -> [{Ecto.UUID.generate(), &1, income}]
          nil -> []
        end
      )

    [next_dividends_companies: next_dividends_companies]
  end

  defreaction maybe_pay_company_dividends(%{projection: projection} = reaction_ctx) do
    if next_company = get_in(projection.next_dividends_companies, [Access.at(0)]) do
      {event_id, company, income} = next_company
      payload = [company: company, income: income]

      metadata =
        Metadata.for_command(
          trace_id: projection.__trace_id__,
          id: event_id,
          user: :game
        )

      command = command("pay_company_dividends", payload, metadata)
      ReactionCtx.issue_if_unsent(reaction_ctx, command)
    end
  end

  handle_event "company_dividends_paid", ctx do
    next_dividends_companies =
      List.keydelete(ctx.projection.next_dividends_companies, ctx.payload.command_id, 0)

    [next_dividends_companies: next_dividends_companies]
  end

  defreaction maybe_end_dividends(%{projection: projection}) do
    case projection.next_dividends_companies do
      [] -> event_builder("dividends_paid")
      _ -> nil
    end
  end

  handle_event "dividends_paid", _ctx do
    [next_dividends_companies: nil]
  end

  handle_event "initial_rail_link_built", ctx do
    %{company: company, link_income: link_income} = ctx.payload
    [company_incomes: Map.put(ctx.projection.company_incomes, company, link_income)]
  end
end
