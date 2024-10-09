# TODO add moduledoc
defmodule TransSiberianRailroad.Aggregator.Players do
  use TransSiberianRailroad.Aggregator
  alias TransSiberianRailroad.Messages
  alias TransSiberianRailroad.Player

  @type t() :: [Player.t()]

  @spec new() :: t()
  def new(), do: []

  #########################################################
  # CONSTRUCTORS
  #########################################################

  @impl true
  # TODO should init be private?
  def init() do
    []
  end

  #########################################################
  # REDUCERS (command handlers)
  #########################################################

  defp handle_command(players, "add_player", payload) do
    %{player_name: player_name} = payload
    player_id = length(players) + 1
    # TODO sequence_number is just a placeholder
    metadata = [sequence_number: 666]

    if player_id <= 5 do
      Messages.player_added(player_id, player_name, metadata)
    else
      Messages.player_rejected(
        "'#{player_name}' cannot join the game. There are already 5 players.",
        metadata
      )
    end
  end

  #########################################################
  # REDUCERS (event handlers)
  #########################################################

  defp handle_event(players, "player_added", payload) do
    %{player_id: player_id, player_name: player_name} = payload
    new_player = Player.new(player_id, player_name)
    [new_player | players]
  end

  defp handle_event(players, "game_started", %{starting_money: starting_money}) do
    for %Player{} = player <- players do
      %Player{player | money: starting_money}
    end
  end

  # TODO the fallback should only match on events whose names are not handled by this module.
  # In other words, I want to force a failuse if I fat-finder a payload key.

  #########################################################
  # REDUCERS
  #########################################################

  @impl true
  # TODO
  def put_version(players, _sequence_number), do: players

  @spec add(t(), Player.id(), String.t()) :: t()
  def add(players, player_id, player_name) do
    added_player = Player.new(player_id, player_name)
    [added_player | players]
  end

  #########################################################
  # CONVERTERS
  #########################################################

  def count(players), do: length(players)

  # TODO rename players -> player_order
  def player_order_once_around_the_table(players, current_player) do
    player_count = count(players)

    player_order_generator(players, current_player)
    |> Enum.take(player_count)
  end

  @spec to_list(t()) :: [Player.t()]
  def to_list(players), do: players

  #########################################################
  # HELPERS
  #########################################################

  # TODO move this elsewhere
  @spec player_order_generator([3..5], 3..5) :: term()
  def player_order_generator(player_order, start_player) do
    player_order
    |> Stream.cycle()
    |> Stream.drop_while(&(&1 != start_player))
  end
end
