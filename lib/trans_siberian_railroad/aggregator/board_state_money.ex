defmodule TransSiberianRailroad.Aggregator.BoardState.Money do
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
  end

  #########################################################
  # :entity_rubles
  #########################################################

  handle_event "money_transferred", ctx do
    transfers = ctx.payload.transfers
    entity_rubles = ctx.projection.entity_rubles

    entity_rubles =
      Enum.reduce(transfers, entity_rubles, fn
        {entity, amount}, balances -> Map.update(balances, entity, amount, &(&1 + amount))
      end)

    [entity_rubles: entity_rubles]
  end

  handle_event "rail_link_built", ctx do
    %{company: company, rubles: rubles} = ctx.payload

    entity_rubles =
      ctx.projection.entity_rubles
      |> Map.update(company, -rubles, &(&1 - rubles))
      |> Map.update(:bank, rubles, &(&1 + rubles))

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

    &Messages.company_money_validated(company, rubles, maybe_error, &1)
  end

  #########################################################
  # game end money
  #########################################################

  handle_event "game_end_sequence_started", _ctx do
    [do_game_end_player_money: true]
  end

  defreaction maybe_game_end_player_money(%{projection: projection}) do
    if projection.do_game_end_player_money do
      entity_rubles =
        projection.entity_rubles
        |> Stream.filter(fn {player, _money} -> Constants.is_player(player) end)
        |> Stream.map(fn {player, money} -> %{player: player, money: money} end)
        |> Enum.sort_by(& &1.player)

      &Messages.game_end_player_money_calculated(entity_rubles, &1)
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
