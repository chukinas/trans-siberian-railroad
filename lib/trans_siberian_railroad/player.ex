defmodule TransSiberianRailroad.Player do
  use TypedStruct

  @type id() :: 1..5

  typedstruct enforce: true do
    field :id, id()
    field :name, String.t()
    field :money, non_neg_integer()
  end

  # TODO move this to Players?
  @spec new(id(), String.t()) :: t()
  def new(player_id, player_name) do
    %__MODULE__{
      id: player_id,
      name: player_name,
      money: 0
    }
  end

  #########################################################
  # HELPERS
  #########################################################

  defguard is_id(x) when x in 1..5
end
