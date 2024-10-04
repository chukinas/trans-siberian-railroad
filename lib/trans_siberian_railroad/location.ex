defmodule TransSiberianRailroad.Location do
  @moduledoc """
  A location is a city or an external linkage.
  RailLinks are built between rail links.
  """

  use TypedStruct

  @type id() :: String.t()

  typedstruct enforce: true do
    field :id, String.t()
    field :name, String.t()
  end

  def new(id, name) do
    %__MODULE__{
      id: id,
      name: name
    }
  end
end
