defmodule TransSiberianRailroad.GameTestHelpers do
  alias TransSiberianRailroad.Game
  alias TransSiberianRailroad.Event
  alias TransSiberianRailroad.Messages
  alias TransSiberianRailroad.Players

  #########################################################
  # Setups
  #########################################################

  def start_game(context) do
    player_count = context[:player_count] || Enum.random(3..5)
    start_player = context[:starting_player] || Enum.random(1..player_count)
    player_order = Enum.to_list(context[:player_order] || Enum.shuffle(1..player_count))
    one_round = Players.one_round(player_order, start_player)

    game =
      Game.handle_commands([
        Messages.initialize_game(),
        add_player_commands(player_count),
        Messages.set_start_player(start_player),
        Messages.set_player_order(player_order),
        Messages.start_game()
      ])

    {:ok,
     game: game,
     start_player: start_player,
     player_count: player_count,
     player_order: player_order,
     one_round: one_round}
  end

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

  def player_order(events) do
    fetch_single_event_payload!(events, "player_order_set").player_order
  end

  def starting_player(events) do
    fetch_single_event_payload!(events, "start_player_set").start_player
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

  def filter_events_by_name(events, event_name, opts \\ []) do
    events = Enum.filter(events, &(&1.name == event_name))

    if opts[:asc] do
      Enum.reverse(events)
    else
      events
    end
  end

  def get_latest_event_by_name(events, event_name) do
    Enum.find(events, &(&1.name == event_name))
  end

  #########################################################
  # Money
  #########################################################

  def current_money(game, player_id) do
    Enum.reduce(game.events, 0, fn event, balance ->
      case event.name do
        "money_transferred" ->
          amount = Map.get(event.payload.transfers, player_id, 0)
          balance + amount

        _ ->
          balance
      end
    end)
  end
end
