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

  typedstruct opaque: true, enforce: true do
    projection_fields()
    field :next_reaction, :end, enforce: false
  end

  #########################################################
  # Start and end the sequence
  #########################################################

  handle_event "end_of_turn_sequence_started", _ctx do
    [next_reaction: :end]
  end

  defreaction maybe_end_sequence(projection) do
    if projection.next_reaction == :end do
      metadata = Projection.next_metadata(projection)
      Messages.end_of_turn_sequence_ended(metadata)
    end
  end

  handle_event "end_of_turn_sequence_ended", _ctx do
    [next_reaction: nil]
  end
end
