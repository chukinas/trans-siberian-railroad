defmodule TransSiberianRailroad.Aggregator.IncomeTrack do
  @moduledoc """
  Tracks the income of each company and pays out dividends
  (`company_dividends_paid` and `dividends_paid`) in response to a `pay_dividends` command.
  """
  use TransSiberianRailroad.Aggregator
  use TransSiberianRailroad.Projection
  alias TransSiberianRailroad.Income
  alias TransSiberianRailroad.Messages
  alias TransSiberianRailroad.Constants

  aggregator_typedstruct do
    plugin TransSiberianRailroad.Reactions
    field :company_incomes, %{Constants.company() => Income.t()}, default: %{red: 2}

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
    &Messages.paying_dividends(&1)
  end

  handle_event "paying_dividends", ctx do
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

  defreaction maybe_pay_company_dividends(projection, reaction_ctx) do
    if next_company = get_in(projection.next_dividends_companies, [Access.at(0)]) do
      {event_id, company, income} = next_company
      metadata = Projection.metadata(projection, id: event_id, user: :game)

      Messages.pay_company_dividends(company, income, metadata)
      |> reaction_ctx.if_unsent.()
    end
  end

  handle_event "company_dividends_paid", ctx do
    next_dividends_companies =
      List.keydelete(ctx.projection.next_dividends_companies, ctx.payload.command_id, 0)

    [next_dividends_companies: next_dividends_companies]
  end

  defreaction maybe_end_dividends(projection, _reaction_ctx) do
    case projection.next_dividends_companies do
      [] -> &Messages.dividends_paid(&1)
      _ -> nil
    end
  end

  handle_event "dividends_paid", _ctx do
    [next_dividends_companies: nil]
  end
end
