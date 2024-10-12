defmodule TransSiberianRailroad.Metadata do
  # TODO make a not somewhere of whether version is 0-based or 1-based
  # TODO this current only works for Auction. Need to generalize.
  def from_aggregator(%{last_version: version}, offset \\ 0) do
    [sequence_number: version + 1 + offset]
  end

  defguard is(metadata) when is_list(metadata) and length(metadata) == 1
end
