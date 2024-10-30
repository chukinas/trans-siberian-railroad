defmodule TransSiberianRailroad.GameHelpers do
  require TransSiberianRailroad.Player, as: Player
  alias TransSiberianRailroad.Game

  def find_command(game, command_name) do
    Enum.find(game.commands, &(&1.name == command_name))
  end

  #########################################################
  # REDUCERS
  #########################################################

  def handle_commands(game \\ Game.new(), commands) do
    commands =
      commands
      |> List.flatten()
      |> Enum.reject(&is_nil/1)

    Enum.reduce(commands, game, &handle_one_command(&2, &1))
  end

  def handle_one_command(game \\ Game.new(), command) do
    game
    |> Game.queue_command(command)
    |> Game.execute()
  end

  def handle_one_event(game, event) do
    game
    |> Game.__queue_event__(event)
    |> Game.execute()
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

  def players_money(game) do
    Enum.reduce(game.events, %{}, fn event, balances ->
      case event.name do
        "money_transferred" ->
          event.payload.transfers
          |> Enum.filter(fn {player_id, _} -> Player.is_id(player_id) end)
          |> Enum.reduce(balances, fn {player_id, amount}, balances ->
            Map.update(balances, player_id, amount, &(&1 + amount))
          end)

        _ ->
          balances
      end
    end)
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

  def globally_sort_messages(game) do
    grouped =
      Stream.concat(game.events, game.commands)
      |> Enum.group_by(& &1.trace_id)
      |> Stream.map(fn {trace_id, messages} ->
        {trace_id, Enum.sort_by(messages, & &1.global_version)}
      end)
      |> Enum.sort_by(fn {_trace_id, [message | _]} -> message.global_version end)

    Enum.chunk_by(grouped, fn {_trace_id, messages} ->
      !!Enum.find(messages, &String.contains?(&1.name, "reject"))
    end)
    |> case do
      [no_rejections, [first_rejection | _] | _] -> no_rejections ++ [first_rejection]
      [no_rejections | _] -> no_rejections
    end
  end
end