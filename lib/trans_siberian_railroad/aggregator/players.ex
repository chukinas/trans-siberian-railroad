# TODO add moduledoc
defmodule TransSiberianRailroad.Aggregator.Players do
  alias TransSiberianRailroad.Event
  alias TransSiberianRailroad.Player

  @type t() :: [Player.t()]

  @spec new() :: t()
  def new(), do: []

  #########################################################
  # CONSTRUCTORS
  #########################################################

  # TODO This should be abstracted away into a behaviour
  defp init() do
    []
  end

  # TODO rename to `from_events`?
  # TODO is this the right name for this?
  def state(events) do
    Event.sort(events)
    |> Enum.reduce(init(), fn %Event{name: event_name, payload: payload}, state ->
      handle_event(state, event_name, payload)
    end)
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

  # TODO The fallback should be injected in a using statement.
  # It should only match on events whose names are not handled by this module.
  # In other words, I want to force a failuse if I fat-finder a payload key.
  defp handle_event(players, _unhandled_event_name, _unhandled_payload), do: players

  #########################################################
  # REDUCERS
  #########################################################

  @spec add(t(), Player.id(), String.t()) :: t()
  def add(players, player_id, player_name) do
    added_player = Player.new(player_id, player_name)
    [added_player | players]
  end

  #########################################################
  # CONVERTERS
  #########################################################

  def count(players), do: length(players)

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

  def starting_money(player_count)
  def starting_money(3), do: 48
  def starting_money(4), do: 40
  def starting_money(5), do: 32

  @spec player_order_generator([3..5], 3..5) :: term()
  def player_order_generator(player_order, start_player) do
    player_order
    |> Stream.cycle()
    |> Stream.drop_while(&(&1 != start_player))
  end
end
