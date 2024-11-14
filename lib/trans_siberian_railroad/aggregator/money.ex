defmodule TransSiberianRailroad.Aggregator.Money do
  @moduledoc """
  track money held by entities (players and companies)
  """

  use TransSiberianRailroad.Aggregator
  use TransSiberianRailroad.Projection
  require TransSiberianRailroad.Constants, as: Constants
  alias TransSiberianRailroad.Messages

  #########################################################
  # PROJECTION
  #########################################################

  aggregator_typedstruct do
    field :player_money, %{Constants.player() => non_neg_integer()}, default: %{}
    field :do_game_end_player_money, boolean(), default: false
  end

  #########################################################
  # :player_money
  #########################################################

  handle_event "money_transferred", ctx do
    transfers = ctx.payload.transfers
    player_money = ctx.projection.player_money

    new_player_money_balances =
      Enum.reduce(transfers, player_money, fn
        {entity, amount}, balances when Constants.is_player(entity) ->
          Map.update(balances, entity, amount, &(&1 + amount))

        _, balances ->
          balances
      end)

    [player_money: new_player_money_balances]
  end

  #########################################################
  # game end money
  #########################################################

  handle_event "game_end_sequence_begun", _ctx do
    [do_game_end_player_money: true]
  end

  defreaction maybe_game_end_player_money(projection, _ctx) do
    if projection.do_game_end_player_money do
      player_money =
        projection.player_money
        |> Enum.map(fn {player, money} -> %{player: player, money: money} end)
        |> Enum.sort_by(& &1.player)

      &Messages.game_end_player_money_calculated(player_money, &1)
    end
  end

  handle_event "game_end_player_money_calculated", _ctx do
    [do_game_end_player_money: false]
  end
end
