defmodule TransSiberianRailroad.Aggregator.Interturn do
  @moduledoc """
  This handles the housekeeping in between players' turns

  Begins when it hears the `interturn_started` event and ends by emitting an `interturn_ended` event.

  An interturn consists of the following steps:
  - pay dividends
  - If Phase 1: check for phase shift (e.g. from phase 1 to phase 2). If so,
    start the phase 2 auction of `"black"` and `"white"` companies.
  - If Phase 2: check for nationalization
  - perform stock adjustments
  - adjust markers
  - check for end of game

  - nationalize companies that are performing poorly
  """

  use TransSiberianRailroad.Aggregator

  aggregator_typedstruct do
    plugin TransSiberianRailroad.Reactions
    field :next_event, Event.t()
  end

  #########################################################
  # Start and end the sequence
  #########################################################

  handle_event "interturn_started", ctx do
    command = Messages.pay_dividends(user: :game, trace_id: ctx.trace_id)
    put_next_command(command)
  end

  handle_event "dividends_paid", ctx do
    metadata = Projection.next_metadata(ctx.projection)
    next_event = Messages.timing_track_reset(metadata)
    put_next_event(next_event)
  end

  defreaction maybe_next_event(%{projection: projection} = reaction_ctx) do
    if event = projection.next_event, do: ReactionCtx.issue_if_unsent(reaction_ctx, event)
  end

  handle_event "timing_track_reset", ctx do
    case ctx.projection.next_event do
      %Event{id: id} when id == ctx.event.id -> clear()
      _ -> nil
    end
  end

  handle_event "interturn_ended", _ctx do
    clear()
  end

  #########################################################
  # REDUCERS
  #########################################################

  defp put_next_command(command) do
    set_next_command(command)
    |> Keyword.put(:next_event, nil)
  end

  defp put_next_event(event) do
    set_next_command(nil)
    |> Keyword.put(:next_event, event)
  end

  defp clear() do
    put_next_event(nil)
  end
end
