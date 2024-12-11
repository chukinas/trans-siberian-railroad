defmodule TsrWeb.MapLayout do
  @moduledoc """
  One every single render, the main geometry of the game board is not going to change.
  This struct ensures that all the calculations are done only once.
  """

  use TypedStruct
  alias Tsr.RailLinks
  alias TsrWeb.GameState
  alias TsrWeb.MapLayout.LocationCoords

  # e.g. "smolensk"
  @typep location() :: String.t()

  # e.g. ["moscow", "smolensk"]
  @typep rail_link() :: [String.t()]

  # e.g. {1508, 1880}
  @typep coord() :: {integer(), integer()}

  typedstruct enforce: true do
    field :viewbox, term()
    field :landmass_coords, term()
    field :moscow_xy, coord()
    field :locations_and_coords, %{location() => coord()}
    field :income_box_coords, term()
    field :rail_links_and_segments, %{rail_link() => [coord()]}
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
        with {x, y} = Map.fetch!(location_coords, "moscow") do
          %{x: x, y: y}
        end,
      locations_and_coords: LocationCoords.get(scale),

      # Income Boxes
      income_box_coords: income_box_coords,

      # Rail Segments
      rail_links_and_segments:
        RailLinks.all()
        |> Map.new(fn rail_link ->
          location_coords = Enum.map(rail_link, &location_coords[&1])
          {x2, y2} = income_box_coords[rail_link]
          segments = Enum.map(location_coords, fn {x1, y1} -> {x1, y1, x2, y2} end)
          {rail_link, segments}
        end)
    }
  end

  #########################################################
  # Converters
  #########################################################

  def income_dice(%__MODULE__{} = map, %GameState{} = game_state) do
    for rail_link <- GameState.rail_links(game_state, :unclaimed) do
      income = RailLinks.income(rail_link)
      {x, y} = map.income_box_coords[rail_link]
      {x, y, income}
    end
  end

  def ext_loc_coords(%__MODULE__{} = map, %GameState{} = game_state, owner) do
    loc_ext = fn loc ->
      String.starts_with?(loc, "ext_") and loc != "moscow"
    end

    GameState.locations(game_state, owner)
    |> Stream.filter(loc_ext)
    |> Enum.map(&map.locations_and_coords[&1])
  end

  def int_loc_coords(%__MODULE__{} = map, %GameState{} = game_state, owner) do
    loc_int = fn loc ->
      !String.starts_with?(loc, "ext_") and loc != "moscow"
    end

    GameState.locations(game_state, owner)
    |> Stream.filter(loc_int)
    |> Enum.map(&map.locations_and_coords[&1])
  end

  def segments(%__MODULE__{} = map, %GameState{} = game_state, owner) do
    GameState.rail_links(game_state, owner)
    |> Enum.flat_map(&map.rail_links_and_segments[&1])
  end
end
