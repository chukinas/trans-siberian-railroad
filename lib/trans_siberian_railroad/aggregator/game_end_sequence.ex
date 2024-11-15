defmodule TransSiberianRailroad.Aggregator.GameEndSequence do
  @moduledoc """
  Determines the winner of the game after the game ends.

  The end-game conditions are handled elsewhere.
  """
  use TransSiberianRailroad.Aggregator

  aggregator_typedstruct do
    field :game_id, term()
    field :player_money, term()
    field :player_stock_values, term()
    field :player_scores, term()
  end

  #########################################################
  # Game ID
  #########################################################

  handle_event "game_initialized", ctx do
    [game_id: ctx.payload.game_id]
  end

  #########################################################
  # Begin game end sequence
  #########################################################

  handle_command "end_game", ctx do
    %{causes: causes} = ctx.payload
    &Messages.game_end_sequence_begun(causes, &1)
  end

  handle_event "game_end_player_money_calculated", ctx do
    [player_money: ctx.payload.player_money]
  end

  handle_event "game_end_player_stock_values_calculated", ctx do
    [player_stock_values: ctx.payload.player_stock_values]
  end

  defreaction maybe_calculate_player_scores(%{projection: projection}) do
    with player_money when is_list(player_money) <- projection.player_money,
         player_stock_values when is_list(player_stock_values) <- projection.player_stock_values do
      player_scores =
        Stream.concat(player_money, player_stock_values)
        |> Enum.group_by(& &1.player, fn
          %{money: money} -> money
          %{total_value: total_stock_value} -> total_stock_value
        end)
        |> Enum.map(fn {player, individual_scores} ->
          total_score = Enum.sum(individual_scores)
          %{player: player, score: total_score}
        end)
        |> Enum.sort_by(& &1.player)

      &Messages.player_scores_calculated(player_scores, &1)
    end
  end

  handle_event "player_scores_calculated", ctx do
    [player_money: nil, player_stock_values: nil, player_scores: ctx.payload.player_scores]
  end

  defreaction maybe_determine_winner(%{projection: projection}) do
    with player_scores when is_list(player_scores) <- projection.player_scores do
      max_score = player_scores |> Enum.map(& &1.score) |> Enum.max()

      winners =
        Enum.flat_map(player_scores, fn
          %{player: player, score: ^max_score} -> [player]
          _ -> []
        end)

      game_id = projection.game_id

      [
        &Messages.winners_determined(winners, max_score, &1),
        &Messages.game_ended(game_id, &1)
      ]
    end
  end

  handle_event "game_ended", _ctx do
    [player_scores: nil]
  end
end
