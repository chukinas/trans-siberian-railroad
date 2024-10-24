defmodule TransSiberianRailroad.Aggregator.EndOfTurn do
  @moduledoc """
  This handles the housekeeping in between players' turns

  Events that might get triggered:
  - pay out dividends
  - end the game
  - start the phase 2 auction of :black and :white companies
  - nationalize companies that are performing poorly
  """

  use TransSiberianRailroad.Aggregator
  use TransSiberianRailroad.Projection
  alias TransSiberianRailroad.Messages

  #########################################################
  # PROJECTION
  #########################################################

  aggregator_typedstruct do
    field :timing_track, 0..5, default: 0
    field :reaction_queue, [event_name :: String.t()], default: []
  end

  #########################################################
  # Timing track
  #########################################################

  handle_event "timing_track_reset", _ctx do
    [timing_track: 0]
  end

  handle_event "timing_track_incremented", ctx do
    timing_track = ctx.projection.timing_track + 1
    timing_track = min(5, timing_track)
    [timing_track: timing_track]
  end

  #########################################################
  # Start and end the sequence
  #########################################################

  @reaction_queue_elements %{
    "awaiting_dividends" => &Messages.awaiting_dividends/1,
    "end_of_turn_sequence_ended" => &Messages.end_of_turn_sequence_ended/1
  }

  for event_name <- Map.keys(@reaction_queue_elements) do
    Aggregator.register_reaction(event_name, __ENV__)
  end

  handle_event "end_of_turn_sequence_started", ctx do
    reaction_queue = ["end_of_turn_sequence_ended"]

    reaction_queue =
      if ctx.projection.timing_track == 5 do
        ["awaiting_dividends" | reaction_queue]
      else
        reaction_queue
      end

    [reaction_queue: reaction_queue]
  end

  defreaction process_reaction_queue(projection) do
    with [event_name | _] <- projection.reaction_queue,
         :ok <- Aggregator.validate_unsent(projection, event_name),
         {:ok, event_builder} <- Map.fetch(@reaction_queue_elements, event_name) do
      event_builder
    else
      :error ->
        require Logger

        Logger.warning("""
        The hd element of the reaction queue is not a handled event.
        #{inspect(projection.reaction_queue)}
        """)

      _ ->
        nil
    end
  end

  handle_event "dividends_paid", ctx do
    pop_reaction_queue(ctx.projection, "awaiting_dividends")
  end

  handle_event "end_of_turn_sequence_ended", ctx do
    pop_reaction_queue(ctx.projection, "end_of_turn_sequence_ended")
  end

  defp pop_reaction_queue(projection, event_name) do
    reaction_queue = Enum.reject(projection.reaction_queue, &(&1 == event_name))
    [reaction_queue: reaction_queue]
  end
end
