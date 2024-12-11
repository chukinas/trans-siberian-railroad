defmodule TsrWeb.Map do
  @moduledoc """
  One every single render, the main geometry of the game board is not going to change.
  This struct ensures that all the calculations are done only once.
  """

  use TypedStruct
  alias Tsr.RailLinks
  alias TsrWeb.MapLayout.LocationCoords

  typedstruct enforce: true do
    field :viewbox, term()
    field :landmass_coords, term()
    field :rail_link_segments, term()
    field :moscow_xy, term()
    field :internal_location_coords, term()
    field :external_location_coords, term()
    field :income_box_coords, term()
  end

  #########################################################
  # Constructors
  #########################################################

  def new(scale) do
    location_coords = TsrWeb.MapLayout.LocationCoords.get(scale)
    income_box_coords = TsrWeb.MapLayout.IncomeDieCoords.get(scale)

    %__MODULE__{
      viewbox: TsrWeb.MapLayout.LandmassCoords.viewbox(scale),
      landmass_coords: TsrWeb.MapLayout.LandmassCoords.coords(scale),

      # Locations
      moscow_xy:
        with {x, y} = LocationCoords.moscow(scale) do
          %{x: x, y: y}
        end,
      internal_location_coords: LocationCoords.internal(scale),
      external_location_coords: LocationCoords.external(scale),

      # Income Boxes
      income_box_coords: income_box_coords,

      # Rail Segments
      rail_link_segments:
        RailLinks.all()
        |> Enum.flat_map(fn rail_link ->
          location_coords = Enum.map(rail_link, &location_coords[&1])
          {x2, y2} = income_box_coords[rail_link]
          Enum.map(location_coords, fn {x1, y1} -> {x1, y1, x2, y2} end)
        end)
    }
  end

  #########################################################
  # Converters
  #########################################################

  def income_dice(%__MODULE__{} = map) do
    for {rail_link, income} <- RailLinks.incomes() do
      {x, y} = map.income_box_coords[rail_link]
      {x, y, income}
    end
  end
end
