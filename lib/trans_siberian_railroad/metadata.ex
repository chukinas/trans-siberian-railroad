defmodule TransSiberianRailroad.Metadata do
  @moduledoc """
  Metadata is data used by the messaging engine that is NOT the state of the domain.

  Metadata is rather slim right now (contains only version number),
  but will be augmented in the future with:
  - a timestamp
  - a user id
  - a trace id
  - uuid
  """

  @type t() :: Keyword.t()

  def new(version) do
    [version: version]
  end

  defguard is(metadata) when is_list(metadata) and length(metadata) == 1
end
