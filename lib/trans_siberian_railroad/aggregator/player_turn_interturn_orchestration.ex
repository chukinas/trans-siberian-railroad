defmodule Tsr.Aggregator.PlayerTurnInterturnOrchestration do
  @moduledoc """
  This handles the housekeeping in between players' turns

  Events that might get triggered:
  - pay out dividends
  - end the game
  - start the phase 2 auction of "black" and :white companies
  - nationalize companies that are performing poorly
  """

  use Tsr.Aggregator
  require Tsr.Reactions, as: Reactions

  aggregator_typedstruct do
    field :end_turn, pos_integer()
    plugin Reactions
  end

  handle_event "auction_phase_ended", ctx do
    if ctx.payload.phase == 1 do
      command("start_player_turn", user: :game, trace_id: ctx.trace_id)
      |> set_next_command()
    end
  end

  #########################################################
  # End Player Turn
  #########################################################

  defp end_turn(ctx) do
    %{player: player} = ctx.payload
    [end_turn: player]
  end

  handle_event("single_stock_purchased", ctx, do: end_turn(ctx))
  handle_event("two_stock_certificates_purchased", ctx, do: end_turn(ctx))
  handle_event("internal_rail_link_built", ctx, do: end_turn(ctx))
  handle_event("two_internal_rail_links_built", ctx, do: end_turn(ctx))
  handle_event("passed", ctx, do: end_turn(ctx))

  defreaction maybe_end_player_turn(reaction_ctx) do
    if player = reaction_ctx.projection.end_turn do
      event_builder("player_turn_ended", player: player)
    end
  end

  handle_event "player_turn_ended", ctx do
    command("start_interturn", user: :game, trace_id: ctx.trace_id)
    |> set_next_command()
    |> Keyword.put(:end_turn, nil)
  end

  #########################################################
  # Maybe Start Interturn
  #########################################################

  handle_event "interturn_started", _projection do
    set_next_command(nil)
  end

  handle_event "interturn_ended", ctx do
    command("start_player_turn", user: :game, trace_id: ctx.trace_id)
    |> set_next_command()
  end

  handle_event "interturn_skipped", ctx do
    command("start_player_turn", user: :game, trace_id: ctx.trace_id)
    |> set_next_command()
  end
end
