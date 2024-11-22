defmodule TransSiberianRailroad.Aggregator.BoardState.Rubles do
  @moduledoc """
  track money held by entities (players and companies)
  """

  use TransSiberianRailroad.Aggregator

  #########################################################
  # PROJECTION
  #########################################################

  aggregator_typedstruct do
    field :entity_rubles, %{Constants.player() => non_neg_integer()}, default: %{}
    field :do_game_end_player_money, boolean(), default: false

    field :pending_transfers,
          [
            %{
              trace_id: Ecto.UUID.t(),
              from: term(),
              to: term(),
              rubles: pos_integer(),
              reason: String.t()
            }
          ],
          default: []
  end

  #########################################################
  # :entity_rubles
  #########################################################

  defp transfer(entity_rubles, rubles, from, to) do
    entity_rubles
    |> Map.update(to, rubles, &(&1 + rubles))
    |> Map.update(from, -rubles, &(&1 - rubles))
  end

  handle_event "game_started", ctx do
    %{players: players} = ctx.payload
    player_count = Enum.count(players)

    starting_rubles =
      case player_count do
        3 -> 48
        4 -> 40
        5 -> 32
      end

    pending_transfers =
      Enum.map(players, fn player ->
        %{
          trace_id: ctx.trace_id,
          from: :bank,
          to: player,
          rubles: starting_rubles,
          reason: "starting rubles"
        }
      end)

    [pending_transfers: pending_transfers ++ ctx.projection.pending_transfers]
  end

  handle_event "player_won_company_auction", ctx do
    %{player: player, company: company, rubles: rubles} = ctx.payload

    pending_transfer = %{
      trace_id: ctx.trace_id,
      from: player,
      to: company,
      rubles: rubles,
      reason: "company stock auctioned off"
    }

    [pending_transfers: [pending_transfer | ctx.projection.pending_transfers]]
  end

  handle_event "single_stock_purchased", ctx do
    %{player: player, company: company, rubles: rubles} = ctx.payload

    pending_transfer = %{
      trace_id: ctx.trace_id,
      from: player,
      to: company,
      rubles: rubles,
      reason: "single stock purchased"
    }

    [pending_transfers: [pending_transfer | ctx.projection.pending_transfers]]
  end

  defreaction maybe_transfer_money(reaction_ctx) do
    Enum.map(reaction_ctx.projection.pending_transfers, fn pt ->
      transfers = [
        %{entity: pt.from, rubles: -pt.rubles},
        %{entity: pt.to, rubles: pt.rubles}
      ]

      fn metadata ->
        metadata = Metadata.for_event(metadata, trace_id: pt.trace_id)

        event_builder("rubles_transferred", transfers: transfers, reason: pt.reason).(metadata)
      end
    end)
  end

  handle_event "rubles_transferred", ctx do
    transfers = ctx.payload.transfers
    entity_rubles = ctx.projection.entity_rubles

    entity_rubles =
      Enum.reduce(transfers, entity_rubles, fn
        %{entity: entity, rubles: rubles}, balances ->
          Map.update(balances, entity, rubles, &(&1 + rubles))
      end)

    pending_transfers =
      Enum.reject(ctx.projection.pending_transfers, &(&1.trace_id == ctx.trace_id))

    [entity_rubles: entity_rubles, pending_transfers: pending_transfers]
  end

  handle_event "internal_rail_link_built", ctx do
    %{company: company} = ctx.payload
    rubles = 4
    [entity_rubles: transfer(ctx.projection.entity_rubles, rubles, company, :bank)]
  end

  handle_event "company_dividends_paid", ctx do
    %{player_payouts: player_payouts} = ctx.payload

    entity_rubles =
      Enum.reduce(player_payouts, ctx.projection.entity_rubles, fn
        %{player: player, rubles: rubles}, entity_rubles ->
          transfer(entity_rubles, rubles, :bank, player)
      end)

    [entity_rubles: entity_rubles]
  end

  #########################################################
  # company has to pay for rail link
  #########################################################

  handle_command "validate_company_money", ctx do
    %{company: company, rubles: rubles} = ctx.payload

    maybe_error =
      if fetch_entity_money!(ctx.projection, company) < rubles do
        "company has insufficient funds"
      end

    Messages.event_builder("company_money_validated", %{
      company: company,
      rubles: rubles,
      maybe_error: maybe_error
    })
  end

  #########################################################
  # game end money
  #########################################################

  handle_event "game_end_sequence_started", _ctx do
    [do_game_end_player_money: true]
  end

  defreaction maybe_game_end_player_money(%{projection: projection}) do
    if projection.do_game_end_player_money do
      player_money =
        projection.entity_rubles
        |> Stream.filter(fn {player, _money} -> Constants.is_player(player) end)
        |> Stream.map(fn {player, rubles} -> %{player: player, rubles: rubles} end)
        |> Enum.sort_by(& &1.player)

      event_builder("game_end_player_money_calculated", player_money: player_money)
    end
  end

  handle_event "game_end_player_money_calculated", _ctx do
    [do_game_end_player_money: false]
  end

  #########################################################
  # Converters
  #########################################################

  defp fetch_entity_money!(projection, entity) do
    Map.get(projection.entity_rubles, entity, 0)
  end
end
