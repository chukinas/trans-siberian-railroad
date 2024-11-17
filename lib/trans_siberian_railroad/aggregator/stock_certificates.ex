defmodule TransSiberianRailroad.Aggregator.StockCertificates do
  @moduledoc """
  Track stock certificate ownership by companies, players, and bank.

  Each company starts the game with 5 or 3.
  As certificates get auctioned or sold off, they then transfer to the players.

  All of a company's certificates are returned to the bank if
  - it fails to auction off its first certificate or
  - it gets nationalized.
  """
  use TransSiberianRailroad.Aggregator

  @bank_certs Constants.companies()
              |> Enum.zip([5, 5, 5, 5, 3, 3])
              |> Map.new()

  aggregator_typedstruct do
    field :cert_counts,
          %{
            (owning_entity :: Messages.entity()) => %{
              Constants.company() => non_neg_integer()
            }
          },
          default: %{bank: Map.new(@bank_certs)}

    # start out nil, then is set to a uuid after game_initialized,
    # then removed when the reactive event is emitteed
    field :initial_stock_transfer, event_id :: Ecto.UUID.t()
    field :end_game_stock_valuation, %{Constants.company() => non_neg_integer()}
  end

  ########################################################
  # track :cert_counts
  ########################################################

  handle_event "game_initialized", _ctx do
    [initial_stock_transfer: Ecto.UUID.generate()]
  end

  defreaction maybe_initial_stock_transfer(%{projection: projection} = reaction_ctx) do
    if event_id = projection.initial_stock_transfer do
      ReactionCtx.if_uuid_unsent(reaction_ctx, event_id, fn -> initial_transfer(event_id) end)
    end
  end

  defp initial_transfer(event_id) do
    reason = "game initialization"

    event_builders =
      for {company, cert_count} <- @bank_certs do
        &Messages.stock_certificates_transferred(
          company,
          :bank,
          company,
          cert_count,
          reason,
          &1
        )
      end

    List.update_at(event_builders, -1, fn event_from_metadata ->
      &(&1
        |> Metadata.override(id: event_id)
        |> event_from_metadata.())
    end)
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

    initial_stock_transfer = ctx.projection.initial_stock_transfer

    initial_stock_transfer =
      if ctx.event_id == initial_stock_transfer do
        nil
      else
        initial_stock_transfer
      end

    [cert_counts: cert_counts, initial_stock_transfer: initial_stock_transfer]
  end

  ########################################################
  # Check whether company is public or not.
  # (Non-public companies cannot build rail)
  ########################################################

  handle_command "check_is_company_public", ctx do
    %{company: company} = ctx.payload

    if public_cert_count(ctx.projection, company) >= 2 do
      &Messages.company_is_public(company, &1)
    else
      &Messages.company_is_not_public(company, &1)
    end
  end

  ########################################################
  # pay dividends
  ########################################################

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

    if stock_count > 0 do
      pay_company_dividends_events(command_id, company, income, player_cert_counts, stock_count)
    end
  end

  defp pay_company_dividends_events(command_id, company, income, player_cert_counts, stock_count)
       when stock_count > 0 do
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

  ########################################################
  # GAME END PLAYER SCORE
  # It's up to another aggregator to calculate the value
  # of each certificate, but it's this one that
  ########################################################

  handle_event "game_end_stock_values_determined", ctx do
    %{companies: companies} = ctx.payload

    stock_values =
      Map.new(companies, fn %{company: company, stock_value: stock_value} ->
        {company, stock_value}
      end)

    players = players(ctx.projection)

    # A company is only worth anything if it has at least 2 certificates owned by players
    company_cert_count_owned_by_players =
      Constants.companies()
      |> Map.new(fn company ->
        count = public_cert_count(ctx.projection, company)
        {company, count}
      end)

    end_game_stock_valuation =
      for player <- players, company <- Constants.companies() do
        stock_count = ctx.projection.cert_counts[player][company] || 0
        cert_count = company_cert_count_owned_by_players[company]

        value_per =
          if cert_count < 2 do
            0
          else
            stock_values[company] || 0
          end

        %{
          player: player,
          company: company,
          count: stock_count,
          value_per: value_per,
          total_value: value_per * stock_count,
          public_cert_count: cert_count
        }
      end
      |> Enum.reject(&(&1.count == 0))

    [end_game_stock_valuation: end_game_stock_valuation]
  end

  defreaction maybe_game_end_player_stock_values_calculated(%{projection: projection}) do
    if stock_values = projection.end_game_stock_valuation do
      &Messages.game_end_player_stock_values_calculated(stock_values, &1)
    end
  end

  handle_event "game_end_player_stock_values_calculated", _ctx do
    [end_game_stock_valuation: nil]
  end

  ########################################################
  # Converters
  ########################################################

  def public_cert_count(projection, company) do
    projection
    |> players
    |> Enum.map(&(projection.cert_counts[&1][company] || 0))
    |> Enum.sum()
  end

  def players(projection) do
    projection.cert_counts
    |> Map.keys()
    |> Enum.filter(&Constants.is_player/1)
    |> Enum.sort()
  end
end
