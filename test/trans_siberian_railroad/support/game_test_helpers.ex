defmodule TransSiberianRailroad.GameTestHelpers do
  alias TransSiberianRailroad.Aggregator.Companies
  alias TransSiberianRailroad.Aggregator.Players
  alias TransSiberianRailroad.Event
  alias TransSiberianRailroad.Messages

  #########################################################
  # Commands
  #########################################################

  def add_player_commands(player_count) when player_count in 1..6 do
    [
      Messages.add_player("Alice"),
      Messages.add_player("Bob"),
      Messages.add_player("Charlie"),
      Messages.add_player("David"),
      Messages.add_player("Eve"),
      Messages.add_player("Frank")
    ]
    |> Enum.take(player_count)
  end

  #########################################################
  # State (Events) Converters
  #########################################################

  def player_count(events) do
    events |> Players.project() |> Players.count()
  end

  def player_order(events) do
    fetch_single_event_payload!(events, "player_order_set").player_order
  end

  def starting_player(events) do
    fetch_single_event_payload!(events, "start_player_selected").start_player
  end

  def get_active_companies(events) do
    Companies.state(events) |> Companies.get_active()
  end

  def fetch_single_event_payload!(events, event_name) do
    fetch_single_event!(events, event_name).payload
  end

  # Succeeds only if there is one such sought event in the list.
  def fetch_single_event!(events, event_name) do
    case filter_events_by_name(events, event_name) do
      [%Event{} = event] -> event
      events -> raise "Expected exactly one #{inspect(event_name)} event; got #{length(events)}."
    end
  end

  def filter_events_by_name(events, event_name) do
    Enum.filter(events, &(&1.name == event_name))
  end
end
