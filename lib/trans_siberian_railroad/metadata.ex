defmodule TransSiberianRailroad.Metadata do
  # TODO moduledoc
  alias TransSiberianRailroad.Event

  @type t() :: Keyword.t()

  # TODO mv this to projection.ex?
  # TODO make a note somewhere of whether version is 0-based or 1-based
  # TODO this current only works for Auction. Need to generalize.
  def from_aggregator(projection, offset \\ 0) do
    [sequence_number: version_from_aggregator(projection, offset)]
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

  # TODO rename this to make it clearer that it's the NEXT version
  def version_from_aggregator(projection, offset \\ 0) do
    version = TransSiberianRailroad.Projection.fetch_version!(projection)
    version + 1 + offset
  end
end
