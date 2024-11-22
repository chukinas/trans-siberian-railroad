defmodule TransSiberianRailroad.CommandHandling do
  @moduledoc """
  An aggregator has the ability to respond to commands.
  This module provides the machinery to do so.
  """

  alias TransSiberianRailroad.Command
  alias TransSiberianRailroad.Event
  alias TransSiberianRailroad.Messages

  #########################################################
  # For use in Aggregators
  #########################################################

  # Not to be called directly. Called by TransSiberianRailroad.Aggregator.
  defmacro __using__(_) do
    quote do
      import unquote(__MODULE__), only: [handle_command: 3]
      Module.register_attribute(__MODULE__, :handled_command_names, accumulate: true)
      @before_compile unquote(__MODULE__)
    end
  end

  defmacro __before_compile__(_) do
    quote do
      def __handled_command_names__(), do: @handled_command_names
    end
  end

  # 1. Accumulate command names that are handled by the aggregator
  # 2. To be able to spread these calls throughout a projection module
  #    so the message flow can be more easily understood
  defmacro handle_command(command_name, ctx, do: block) do
    valid_command_names = Messages.command_names()

    unless command_name in valid_command_names do
      raise """
      handle_command/3 expects an command name already declared in #{inspect(Messages)}.

      name: #{inspect(command_name)}

      valid names:
      #{inspect(valid_command_names)}
      """
    end

    quote do
      @handled_command_names unquote(command_name)
      def __handle_command__(unquote(command_name), unquote(ctx)) do
        unquote(block)
      end
    end
  end

  #########################################################
  # For use in game engine
  #########################################################

  @spec get_events(struct(), Command.t()) :: [Event.t(), ...] | nil
  def get_events(projection, command) do
    %projection_mod{} = projection
    %Command{name: command_name, payload: payload, trace_id: trace_id} = command

    if command_name in projection_mod.__handled_command_names__() do
      ctx = %{
        projection: projection,
        payload: payload,
        id: command.id
      }

      orig_result = projection_mod.__handle_command__(command_name, ctx)

      case Event.coerce_to_events(orig_result, projection.__version__, trace_id) do
        [] -> nil
        events when is_list(events) -> events
      end
    end
  end
end
