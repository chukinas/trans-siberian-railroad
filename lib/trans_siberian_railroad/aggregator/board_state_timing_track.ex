defmodule TransSiberianRailroad.Aggregator.BoardState.TimingTrack do
  @moduledoc """
  The timing track is a track of 6 spaces that determines when the interturn phase begins.

  The following player actions increment the timing track:
  - purchasing two stock certificates in one turn
  - laying two rail links in one turn
  - passing
  """

  use TransSiberianRailroad.Aggregator

  aggregator_typedstruct do
    plugin TransSiberianRailroad.Reactions
    field :timing_track, 0..5, default: 0
  end

  #########################################################
  # Timing Track
  #########################################################

  handle_event "timing_track_reset", _ctx do
    [timing_track: 0]
  end

  handle_event "passed", ctx do
    timing_track = ctx.projection.timing_track + 1
    timing_track = min(5, timing_track)
    [timing_track: timing_track]
  end

  #########################################################
  # Interturn
  #########################################################

  handle_command "start_interturn", ctx do
    if ctx.projection.timing_track >= 5 do
      &Messages.interturn_started(&1)
    else
      &Messages.interturn_skipped(&1)
    end
  end
end
