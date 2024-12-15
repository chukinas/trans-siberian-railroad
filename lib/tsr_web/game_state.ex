defmodule TsrWeb.GameState do
  @moduledoc """
  This data structure contains all the state needed to represent a current game.
  """

  use TypedStruct
  alias Tsr.RailLinks

  @typep owner() :: :unclaimed | :red | :blue | :green | :yellow | :black | :white

  # e.g. "smolensk"
  @typep location() :: String.t()

  # e.g. ["moscow", "smolensk"]
  @typep rail_link() :: [location()]

  typedstruct enforce: true do
    field :locations, %{owner() => [location()]}
    field :rail_links, %{owner() => [rail_link()]}
    field :latest_rail_link, rail_link(), default: []
  end

  #########################################################
  # Constructors
  #########################################################
  def new() do
    %__MODULE__{
      locations: %{
        unclaimed:
          RailLinks.all()
          |> List.flatten()
          |> Enum.uniq()
          |> Enum.reject(&(&1 == "moscow")),
        red: [],
        blue: [],
        green: [],
        yellow: [],
        black: [],
        white: []
      },
      rail_links: %{
        unclaimed: RailLinks.all(),
        red: [],
        blue: [],
        green: [],
        yellow: [],
        black: [],
        white: []
      }
    }
  end

  #########################################################
  # Reducers
  #########################################################

  def add_rail_link(%__MODULE__{} = game_state, new_owner, rail_link) do
    rail_links =
      Map.new(game_state.rail_links, fn {owner, rail_links} ->
        if owner == new_owner do
          {owner, [rail_link | rail_links]}
        else
          {owner, Enum.reject(rail_links, &(&1 == rail_link))}
        end
      end)

    {owner_locs, unclaimed_locs} =
      Enum.reduce(game_state.locations.unclaimed, {game_state.locations[new_owner], []}, fn loc,
                                                                                            {owner_locs,
                                                                                             unclaimed_locs} ->
        if Enum.member?(rail_link, loc) do
          {[loc | owner_locs], unclaimed_locs}
        else
          {owner_locs, [loc | unclaimed_locs]}
        end
      end)

    locations =
      Map.merge(game_state.locations, %{new_owner => owner_locs, unclaimed: unclaimed_locs})

    %__MODULE__{
      game_state
      | rail_links: rail_links,
        locations: locations,
        latest_rail_link: rail_link
    }
  end

  #########################################################
  # Converters
  #########################################################

  def get_rand_rail_link(%__MODULE__{} = game_state, owner) do
    connected_locs =
      if owner in ~w/black white/a and Enum.empty?(game_state.rail_links[owner]) do
        game_state.rail_links
        |> Map.drop([:unclaimed])
        |> Map.values()
        |> List.flatten()
        |> Enum.uniq()
      else
        connected_locs =
          Map.fetch!(game_state.rail_links, owner)
          |> List.flatten()

        ["moscow" | connected_locs]
        |> Enum.uniq()
      end

    rail_link_contains_connected_loc = fn rail_link ->
      Enum.any?(rail_link, &(&1 in connected_locs))
    end

    game_state.rail_links.unclaimed
    |> Enum.filter(rail_link_contains_connected_loc)
    |> case do
      [] -> nil
      rail_links -> Enum.random(rail_links)
    end
  end

  def latest?(%__MODULE__{latest_rail_link: latest_rail_link}, rail_link)
      when is_list(rail_link) do
    latest_rail_link == rail_link
  end

  # results might include moscow; it's up to the consumer to filter it out
  def locations(%__MODULE__{} = game_state, owner) do
    Map.fetch!(game_state.locations, owner)
  end

  def rail_links(%__MODULE__{} = game_state, owner) do
    Map.fetch!(game_state.rail_links, owner)
  end
end
