defmodule TsrWeb.MapLayout do
  @moduledoc """
  One every single render, the main geometry of the game board is not going to change.
  This struct ensures that all the calculations are done only once.
  """

  use TypedStruct
  alias Tsr.RailLinks
  alias TsrWeb.GameState
  alias TsrWeb.MapLayout.LocationCoords
  alias TsrWeb.MapLayout.LocationNames

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

  def income_die(%__MODULE__{} = map, %GameState{} = game_state, rail_link_id) do
    rail_link = rail_link_from_id!(rail_link_id)
    income = RailLinks.income(rail_link)
    claimed_rail_links = GameState.claimed_rail_links(game_state)
    {x, y} = map.income_box_coords[rail_link]
    %{x: x, y: y, income: income, claimed: rail_link in claimed_rail_links}
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

  def segments(%__MODULE__{} = map, game_state, rail_link_id) when is_integer(rail_link_id) do
    rail_link = rail_link_from_id!(rail_link_id)
    owner = GameState.rail_link_owner!(game_state, rail_link)

    for {x1, y1, x2, y2} <- map.rail_links_and_segments[rail_link] do
      %{x1: x1, y1: y1, x2: x2, y2: y2, owner: owner}
    end
  end

  def location_coord!(%__MODULE__{} = map_layout, location) when is_binary(location) do
    Map.fetch!(map_layout.locations_and_coords, location)
  end

  #########################################################
  # Helpers
  #########################################################

  @sorted_rail_links RailLinks.all()
                     |> Enum.sort()
                     |> Enum.with_index()
                     |> Map.new(fn {rail_link, index} -> {index, rail_link} end)

  @max_rail_link_id @sorted_rail_links |> Map.keys() |> Enum.max()

  def rail_link_ids() do
    0..@max_rail_link_id
  end

  defp rail_link_from_id!(id) do
    Map.fetch!(@sorted_rail_links, id)
  end

  # @rail_links_and_ids Map.new(@sorted_rail_links, fn {id, rail_link} -> {rail_link, id} end)
  # defp rail_link_to_id!(rail_link) do
  #   Map.fetch!(@rail_links_and_ids, rail_link)
  # end

  @location_names LocationNames.get() |> Enum.map(& &1.id) |> Enum.reject(&(&1 == "moscow"))
  def location_names(), do: @location_names
end
