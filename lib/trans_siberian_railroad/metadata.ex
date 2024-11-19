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

  defguard is(metadata) when is_list(metadata)

  def new(version, trace_id \\ Ecto.UUID.generate()) do
    [version: version, trace_id: trace_id]
  end

  def override(metadata, overrides) do
    Enum.reduce(overrides, metadata, fn
      {k, v}, metadata when k in [:id, :trace_id] -> Keyword.put(metadata, k, v)
    end)
  end
end
