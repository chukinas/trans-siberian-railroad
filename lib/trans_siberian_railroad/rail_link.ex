defmodule TransSiberianRailroad.RailLink do
  @moduledoc """
  A rail link is a length of track built between two or more cities or foreign locations.
  It is either unbuilt or build by one of the rail companies.
  Once built, can not be rebuilt or removed.
  """

  use TypedStruct

  typedstruct enforce: true do
    field :id, non_neg_integer()
    field :linked_location_ids, [TransSiberianRailroad.Location.id(), ...]
    field :income, 2..6
    field :owning_railroad, nil | TransSiberianRailroad.Constants.company()
  end

  def new(id, linked_locations, income) when is_integer(id) and id >= 0 and income in 2..6 do
    %__MODULE__{
      id: id,
      linked_location_ids: Enum.sort(linked_locations),
      income: income,
      owning_railroad: nil
    }
  end

  def external_link?(%__MODULE__{linked_location_ids: location_ids}) do
    Enum.any?(location_ids, &String.starts_with?(&1, "ext_"))
  end
end
