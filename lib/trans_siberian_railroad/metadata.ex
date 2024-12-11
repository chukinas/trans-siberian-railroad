defmodule Tsr.Metadata do
  @moduledoc """
  Metadata is data used by the messaging engine that is NOT the state of the domain.
  """

  @type t() :: Keyword.t()

  defguard is(metadata) when is_list(metadata)

  def for_command(metadata \\ [], fields) when is_list(fields) do
    metadata
    |> Keyword.merge(fields)
    |> Keyword.validate!([
      :user,
      id: Ecto.UUID.generate(),
      trace_id: Ecto.UUID.generate()
    ])
  end

  def for_event(metadata \\ [], fields) when is_list(fields) do
    metadata
    |> Keyword.merge(fields)
    |> Keyword.validate!([
      :user,
      :version,
      id: Ecto.UUID.generate(),
      trace_id: Ecto.UUID.generate()
    ])
  end
end
