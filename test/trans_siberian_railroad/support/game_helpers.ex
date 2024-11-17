defmodule TransSiberianRailroad.GameHelpers do
  require TransSiberianRailroad.Constants, as: Constants
  alias TransSiberianRailroad.Event
  alias TransSiberianRailroad.Game
  alias TransSiberianRailroad.Messages
  alias TransSiberianRailroad.Metadata

  @valid_event_names MapSet.new(Messages.event_names())

  def filter_events(%Game{events: events}, event_name, opts \\ []) do
    check_name(event_name)
    events = Enum.filter(events, &(&1.name == event_name))

    if opts[:asc] do
      Enum.reverse(events)
    else
      events
    end
  end

  def get_one_event(game, event_name) do
    check_name(event_name)

    case filter_events(game, event_name) do
      [event] -> event
      [] -> nil
      [_ | _] -> nil
    end
  end

  defp check_name(event_name) do
    unless MapSet.member?(@valid_event_names, event_name) do
      require Logger
      Logger.warning("#{event_name} is not in the list of events")
    end
  end

  def fetch_latest_event!(game, event_name) do
    case get_latest_event(game, event_name) do
      nil -> raise "No #{event_name} event found"
      event -> event
    end
  end

  def get_latest_event(%_{events: events}, event_name) do
    check_name(event_name)
    Enum.find(events, &(&1.name == event_name))
  end

  def find_command(game, command_name) do
    Enum.find(game.commands, &(&1.name == command_name))
  end

  #########################################################
  # REDUCERS
  #########################################################

  def handle_commands(game \\ Game.new(), commands, opts \\ []) do
    commands =
      commands
      |> List.flatten()
      |> Enum.reject(&is_nil/1)

    if Keyword.get(opts, :one_by_one, true) do
      Enum.reduce(commands, game, &handle_one_command(&2, &1))
    else
      Enum.reduce(commands, game, &Game.queue_command(&2, &1))
      |> Game.execute()
    end
  end

  def handle_one_command(game \\ Game.new(), command) do
    game
    |> Game.queue_command(command)
    |> Game.execute()
  end

  def handle_one_event(%Game{events_version: version} = game, event) do
    event =
      cond do
        is_struct(event, Event) -> event
        is_function(event, 1) -> Metadata.new(version + 1) |> event.()
      end

    game
    |> Game.__queue_event__(event)
    |> Game.execute()
  end

  #########################################################
  # Converters
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

  def players_money(game) do
    Enum.reduce(game.events, %{}, fn event, balances ->
      case event.name do
        "money_transferred" ->
          event.payload.transfers
          |> Enum.filter(fn {player_id, _} -> Constants.is_player(player_id) end)
          |> Enum.reduce(balances, fn {player_id, amount}, balances ->
            Map.update(balances, player_id, amount, &(&1 + amount))
          end)

        _ ->
          balances
      end
    end)
  end

  def player_count(game) do
    game
    |> filter_events("player_added")
    |> Enum.count()
  end

  def players(game), do: 1..player_count(game)

  def current_player(game) do
    fetch_latest_event!(game, "player_turn_started").payload.player
  end

  def wrong_player(game) do
    current_player = current_player(game)
    players(game) |> Enum.reject(&(&1 == current_player)) |> Enum.random()
  end

  def rand_player(game) do
    players(game) |> Enum.random()
  end

  #########################################################
  # Views
  #########################################################

  def group_messages_by_trace(game) do
    get_events_by_trace =
      with events_by_trace = Enum.group_by(game.events, & &1.trace_id) do
        fn trace_id ->
          events_by_trace[trace_id]
          |> List.wrap()
          |> Enum.sort_by(& &1.version)
        end
      end

    grouped_messages =
      game.commands
      |> Enum.reverse()
      |> Enum.map(fn command ->
        trace_id = command.trace_id
        events = get_events_by_trace.(trace_id)
        {trace_id, [command | events]}
      end)

    Enum.chunk_by(grouped_messages, fn {_trace_id, messages} ->
      !!Enum.find(messages, &String.contains?(&1.name, "reject"))
    end)
    |> case do
      [no_rejections, [first_rejection | _] | _] -> no_rejections ++ [first_rejection]
      [no_rejections | _] -> no_rejections
    end
  end

  def t(game), do: globally_sort_messages(game)

  def globally_sort_messages(game) do
    grouped =
      Stream.concat(game.events, game.commands)
      |> Enum.group_by(& &1.trace_id)
      |> Stream.map(fn {trace_id, messages} ->
        {trace_id, Enum.sort_by(messages, & &1.global_version)}
      end)
      |> Enum.sort_by(fn {_trace_id, [message | _]} -> message.global_version end)

    # Enum.chunk_by(grouped, fn {_trace_id, messages} ->
    #   !!Enum.find(messages, &String.contains?(&1.name, "reject"))
    # end)
    # |> case do
    #   [no_rejections, [first_rejection | _] | _] -> no_rejections ++ [first_rejection]
    #   [no_rejections | _] -> no_rejections
    # end
    grouped
  end
end
