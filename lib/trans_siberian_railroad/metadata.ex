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

  def new(version, trace_id) do
    [version: version, trace_id: trace_id]
  end
end
