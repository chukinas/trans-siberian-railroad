defmodule TransSiberianRailroad.Metadata do
  @moduledoc """
  Metadata is data used by the messaging engine that is NOT the state of the domain.

  Metadata is rather slim right now, but will be augmented in the future with:
  - a timestamp
  - a user id
  - a trace id
  """

  @type t() :: Keyword.t()

  def new(version) do
    [sequence_number: version]
  end

  defguard is(metadata) when is_list(metadata) and length(metadata) == 1
end
