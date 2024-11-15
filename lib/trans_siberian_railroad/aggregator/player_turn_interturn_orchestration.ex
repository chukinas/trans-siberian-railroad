defmodule TransSiberianRailroad.Aggregator.PlayerTurnInterturnOrchestration do
  @moduledoc """
  This handles the housekeeping in between players' turns

  Events that might get triggered:
  - pay out dividends
  - end the game
  - start the phase 2 auction of "black" and :white companies
  - nationalize companies that are performing poorly
  """

  use TransSiberianRailroad.Aggregator
  require TransSiberianRailroad.Reactions, as: Reactions

  aggregator_typedstruct do
    plugin Reactions
  end

  handle_event "auction_phase_ended", ctx do
    if ctx.payload.phase_number == 1 do
      Messages.start_player_turn(user: :game, trace_id: ctx.trace_id)
      |> set_next_command()
    end
  end

  handle_event "player_turn_ended", ctx do
    Messages.start_interturn(user: :game, trace_id: ctx.trace_id)
    |> set_next_command()
  end

  handle_event "interturn_started", _projection do
    set_next_command(nil)
  end

  handle_event "interturn_ended", ctx do
    Messages.start_player_turn(user: :game, trace_id: ctx.trace_id)
    |> set_next_command()
  end

  handle_event "interturn_skipped", ctx do
    Messages.start_player_turn(user: :game, trace_id: ctx.trace_id)
    |> set_next_command()
  end
end
