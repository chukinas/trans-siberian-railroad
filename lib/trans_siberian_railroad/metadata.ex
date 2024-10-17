defmodule TransSiberianRailroad.Metadata do
  # TODO moduledoc
  alias TransSiberianRailroad.Event

  # TODO make a note somewhere of whether version is 0-based or 1-based
  # TODO this current only works for Auction. Need to generalize.
  def from_aggregator(%{last_version: version}, offset \\ 0) do
    [sequence_number: version + 1 + offset]
  end

  def from_events(events) do
    current_version =
      case events do
        [%Event{sequence_number: version} | _] -> version
        _ -> 0
      end

    # TODO unify the language
    [sequence_number: current_version + 1]
  end

  defguard is(metadata) when is_list(metadata) and length(metadata) == 1
end
