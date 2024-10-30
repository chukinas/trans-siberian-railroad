defmodule TransSiberianRailroad.Aggregator.StockCertificates do
  @moduledoc """
  Source of truth for where the stock certificates are at any time.

  Each company starts the game with 5 or 3.
  As certificates get auctioned or sold off, they then transfer to the players.
  If a company fails to auction off its first certificate, all its certificates are returned to the bank.
  If a company gets nationalized, all its certificates are returned to the bank.
  """
  use TransSiberianRailroad.Aggregator
  use TransSiberianRailroad.Projection
  alias TransSiberianRailroad.Messages
  alias TransSiberianRailroad.Company

  aggregator_typedstruct enforce: true do
    field :cert_counts,
          %{
            (owning_entity :: Messages.entity()) => %{
              Company.id() => non_neg_integer()
            }
          },
          default: %{
            bank: %{
              red: 5,
              blue: 5,
              green: 5,
              yellow: 5,
              black: 3,
              white: 3
            }
          }
  end

  handle_event "stock_certificates_transferred", ctx do
    %{company: company, from: from, to: to, quantity: quantity} = ctx.payload

    transfers = %{
      from => -quantity,
      to => quantity
    }

    cert_counts = ctx.projection.cert_counts

    cert_counts =
      Enum.reduce(transfers, cert_counts, fn {entity, quantity}, cert_counts ->
        update_in(
          cert_counts,
          [Access.key(entity, %{}), Access.key(company, 0)],
          &(&1 + quantity)
        )
      end)

    [cert_counts: cert_counts]
  end

  handle_command "pay_company_dividends", ctx do
    command_id = ctx.id
    %{company: company, income: income} = ctx.payload
    cert_counts = ctx.projection.cert_counts

    player_cert_counts =
      Enum.flat_map(1..5, fn player ->
        case cert_counts[player][company] do
          count when is_integer(count) and count > 0 -> [{player, count}]
          _ -> []
        end
      end)

    stock_count =
      player_cert_counts
      |> Enum.map(&elem(&1, 1))
      |> Enum.sum()

    certificate_value = ceil(income / stock_count)

    total_value = stock_count * certificate_value

    transfers =
      Map.new(player_cert_counts, fn {player, count} ->
        {player, count * certificate_value}
      end)
      |> Map.put(:bank, -total_value)

    reason = "dividends paid by #{company} at #{certificate_value} per share"

    [
      &Messages.money_transferred(transfers, reason, &1),
      &Messages.company_dividends_paid(
        company,
        income,
        stock_count,
        certificate_value,
        command_id,
        &1
      )
    ]
  end
end
