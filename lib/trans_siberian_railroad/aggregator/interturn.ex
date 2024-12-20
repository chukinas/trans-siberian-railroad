defmodule Tsr.Aggregator.Interturn do
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

  use Tsr.Aggregator

  aggregator_typedstruct do
    field :phase, 1..2, default: 1

    field :next_steps,
          [{message_name :: String.t(), command_or_event_builder :: (String.t() -> term())}],
          default: []
  end

  #########################################################
  # Start and end the sequence
  #########################################################

  defreaction maybe_next_step(reaction_ctx) do
    with [next_step | _] <- reaction_ctx.projection.next_steps do
      case next_step do
        {message_name, message_builder} ->
          message_builder.(reaction_ctx, message_name, %{})

        {message_name, payload, message_builder} ->
          message_builder.(reaction_ctx, message_name, payload)
      end
    else
      _ -> nil
    end
  end

  defp remove_completed_step(event_ctx, message_name) do
    remove_completed_steps(event_ctx, [message_name])
  end

  defp remove_completed_steps(event_ctx, message_names) do
    next_steps = event_ctx.projection.next_steps |> Enum.reject(&(elem(&1, 0) in message_names))
    [next_steps: next_steps]
  end

  handle_event "interturn_started", ctx do
    trace_id = ctx.trace_id
    to_command = &ReactionCtx.command_if_unsent(&1, &2, &3, trace_id: trace_id)
    to_event = &ReactionCtx.event_if_unsent(&1, &2, &3, trace_id)

    next_steps =
      [
        {"pay_dividends", to_command},
        if(ctx.projection.phase == 1,
          do: [
            {"check_phase_shift", to_command},
            {"start_auction_phase", [phase: 2], to_command}
          ]
        ),
        {"timing_track_reset", to_event},
        {"interturn_ended", to_event}
      ]
      |> List.flatten()
      |> Enum.filter(& &1)

    [next_steps: next_steps]
  end

  handle_event "dividends_paid", ctx do
    remove_completed_step(ctx, "pay_dividends")
  end

  handle_event "phase_1_continues", ctx do
    remove_completed_steps(ctx, ["check_phase_shift", "start_auction_phase"])
  end

  handle_event "phase_2_started", ctx do
    remove_completed_step(ctx, "check_phase_shift")
    |> Keyword.put(:phase, 2)
  end

  handle_event "auction_phase_ended", ctx do
    remove_completed_step(ctx, "start_auction_phase")
  end

  handle_event "timing_track_reset", ctx do
    remove_completed_step(ctx, "timing_track_reset")
  end

  handle_event "interturn_ended", ctx do
    remove_completed_step(ctx, "interturn_ended")
  end
end
