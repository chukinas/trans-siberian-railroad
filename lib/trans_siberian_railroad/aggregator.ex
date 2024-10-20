defmodule TransSiberianRailroad.Aggregator do
  @moduledoc """
  An aggregator is responsible for emitting new events.
  It does this by building a projection from the current events list, then:
  - handling commands that may have been issued by the user or the game itself, or
  - emitting new events ("reactions") based on that current projection.
  """

  alias TransSiberianRailroad.Messages
  alias TransSiberianRailroad.Event

  defmacro __using__(_) do
    quote do
      @mod TransSiberianRailroad.Aggregator
      @before_compile @mod
      import TransSiberianRailroad.Aggregator, only: [defreaction: 2, handle_command: 3]
      unquote(accumulate_command_names())
      unquote(accumulate_reactions())
    end
  end

  defmacro __before_compile__(_) do
    quote do
      unquote(inject_handle_command_names_fn())
      unquote(inject_reactions_fn())
    end
  end

  #########################################################
  # Command Handling
  #########################################################

  defp accumulate_command_names() do
    quote do
      Module.register_attribute(__MODULE__, :handled_command_names, accumulate: true)
    end
  end

  # Really, the only reason to have this macro is:
  # 1. To accumulate the command names (if needed)
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

  defp inject_handle_command_names_fn() do
    quote do
      def __handled_command_names__(), do: @handled_command_names
    end
  end

  def handle_one_command(projection, command) do
    %projection_mod{} = projection
    %TransSiberianRailroad.Command{name: command_name, payload: payload} = command

    if command_name in projection_mod.__handled_command_names__() do
      projection_mod.__handle_command__(command_name, %{projection: projection, payload: payload})
      |> List.wrap()
      |> Enum.reject(&is_nil/1)
    else
      []
    end
  end

  #########################################################
  # Reactions
  #########################################################

  defp accumulate_reactions() do
    quote do
      Module.register_attribute(__MODULE__, :__reactions__, accumulate: true)
    end
  end

  defmacro defreaction(projection, do: block) do
    {function_name, _, _} = projection

    quote do
      @__reactions__ Function.capture(__MODULE__, unquote(function_name), 1)
      # TODO privatize
      def(unquote(projection), do: unquote(block))
    end
  end

  defp inject_reactions_fn() do
    quote do
      def events_from_projection(projection) do
        Enum.find_value(@__reactions__, & &1.(projection))
      end
    end
  end

  def reactions(%mod{} = projection) do
    events =
      mod.events_from_projection(projection)
      |> List.wrap()
      |> Enum.reject(&is_nil/1)

    Enum.each(events, fn
      %Event{} -> :ok
      event -> raise "Expected only Events from #{inspect(mod)}, got: #{inspect(event)}"
    end)

    events
  end
end
