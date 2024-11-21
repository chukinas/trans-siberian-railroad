defmodule TransSiberianRailroad.Reaction do
  alias TransSiberianRailroad.Command
  alias TransSiberianRailroad.Event
  alias TransSiberianRailroad.Projection

  defmacro __using__(_) do
    quote do
      import unquote(__MODULE__), only: [defreaction: 2]
      @before_compile unquote(__MODULE__)
      Module.register_attribute(__MODULE__, :__reactions__, accumulate: true)
    end
  end

  defmacro defreaction(projection, do: block) do
    {function_name, _, _} = projection

    quote do
      @__reactions__ unquote(function_name)
      def(unquote(projection), do: unquote(block))
    end
  end

  defmacro __before_compile__(_) do
    quote do
      @__reaction_fns__ Enum.map(@__reactions__, fn fn_name ->
                          arity = Module.definitions_in(__MODULE__)[fn_name]
                          Function.capture(__MODULE__, fn_name, arity)
                        end)

      def get_reaction(projection, reaction_ctx) do
        Enum.find_value(@__reaction_fns__, & &1.(reaction_ctx))
      end
    end
  end

  @type reaction() :: %{
          optional(:events) => [Event.t()],
          optional(:commands) => [Command.t()]
        }
  @doc """
  This is how the game interacts with the reactions defined in an aggregator via `defreaction/2`.
  """
  @spec get_reaction(Projection.t(), map()) :: reaction() | nil
  def get_reaction(%mod{} = projection, reaction_ctx) do
    coerce =
      with metadata = Projection.event_from_offset_builder(projection) do
        &Event.coerce_to_events(&1, metadata)
      end

    result = mod.get_reaction(projection, reaction_ctx)

    maybe_events =
      case result do
        events when is_list(events) -> events
        %Event{} = event -> [event]
        function_builder when is_function(function_builder, 1) -> [function_builder]
        %{events: events} -> events
        _ -> []
      end
      |> coerce.()

    maybe_commands =
      case result do
        %{commands: commands} -> commands
        _ -> []
      end

    [events: maybe_events, commands: maybe_commands]
    |> Enum.filter(fn {_, maybe_list} -> Enum.any?(maybe_list) end)
    |> case do
      [] -> nil
      kv -> Map.new(kv)
    end
  end
end
