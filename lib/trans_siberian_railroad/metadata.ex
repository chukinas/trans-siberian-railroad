defmodule TransSiberianRailroad.Metadata do
  # TODO this current only works for Auction. Need to generalize.
  def from_aggregator(%{last_version: version}, offset \\ 0) do
    [sequence_number: version + 1 + offset]
  end
end