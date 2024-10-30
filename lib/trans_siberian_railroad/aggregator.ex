defmodule TransSiberianRailroad.Aggregator do
  @moduledoc """
  An aggregator is responsible for emitting new events.
  It does this by building a projection from the current events list, then:
  - handling commands that may have been issued by the user or the game itself, or
  - emitting new events ("reactions") based on that current projection.
  """

  alias TransSiberianRailroad.Command
  alias TransSiberianRailroad.Event
  alias TransSiberianRailroad.Messages
  alias TransSiberianRailroad.Projection

  @type t() :: struct()

  defmacro __using__(_) do
    quote do
      @mod TransSiberianRailroad.Aggregator
      @before_compile @mod
      import TransSiberianRailroad.Aggregator,
        only: [
          aggregator_typedstruct: 1,
          aggregator_typedstruct: 2,
          defreaction: 2,
          handle_command: 3
        ]

      require TransSiberianRailroad.Aggregator, as: Aggregator
      unquote(accumulate_command_names())
      unquote(accumulate_reactions())
      unquote(accumulate_sent_reactions())
    end
  end

  defmacro __before_compile__(_) do
    quote do
      unquote(before_compile_commands())
      unquote(before_compile_reactions())
      unquote(before_compile_sent_reactions())
    end
  end

  defmacro aggregator_typedstruct(opts \\ [], do: block) do
    opts = Keyword.put_new(opts, :opaque, true)

    quote do
      typedstruct unquote(opts) do
        projection_fields()

        unquote(__sent_reactions_field__())
        unquote(block)
      end
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

  defp before_compile_commands() do
    quote do
      def __handled_command_names__(), do: @handled_command_names
    end
  end

  @spec maybe_events_from_command(struct(), Command.t()) :: [Event.t(), ...] | nil
  def maybe_events_from_command(projection, command) do
    %projection_mod{} = projection

    %TransSiberianRailroad.Command{name: command_name, payload: payload, trace_id: trace_id} =
      command

    if command_name in projection_mod.__handled_command_names__() do
      metadata = metadata_from_projection(projection, trace_id)
      next_metadata = metadata.(0)

      ctx = %{
        projection: projection,
        payload: payload,
        next_metadata: next_metadata,
        metadata: metadata,
        id: command.id
      }

      orig_result = projection_mod.__handle_command__(command_name, ctx)

      events =
        maybe_events_from_result(orig_result)
        |> maybe_convert_builders_to_events(metadata)

      case events do
        [] -> nil
        _ -> events
      end
    end
  end

  defp maybe_events_from_result(result) do
    case result do
      events when is_list(events) -> events
      %Event{} = event -> [event]
      function_builder when is_function(function_builder, 1) -> [function_builder]
      %{events: events} -> events
      _ -> nil
    end
  end

  defp maybe_commands_from_result(result) do
    case result do
      %{commands: commands} -> commands
      _ -> nil
    end
  end

  defp maybe_convert_builders_to_events(message_builders, metadata_from_index) do
    message_builders
    |> List.wrap()
    |> Enum.reject(&is_nil/1)
    |> case do
      [fun | _] = message_builders when is_function(fun, 1) ->
        message_builders
        |> Enum.with_index()
        |> Enum.map(fn {build_msg, idx} -> build_msg.(metadata_from_index.(idx)) end)

      events ->
        events
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
      @__reactions__ unquote(function_name)
      def(unquote(projection), do: unquote(block))
    end
  end

  defp before_compile_reactions() do
    quote do
      @__reaction_fns__ Enum.map(@__reactions__, fn fn_name ->
                          arity = Module.definitions_in(__MODULE__)[fn_name]

                          Function.capture(__MODULE__, fn_name, arity)
                        end)

      def get_reaction(projection, reaction_ctx) do
        Enum.find_value(@__reaction_fns__, fn fun ->
          cond do
            is_function(fun, 1) -> fun.(projection)
            is_function(fun, 2) -> fun.(projection, reaction_ctx)
          end
        end)
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
  @spec get_reaction(t(), map()) :: reaction() | nil
  def get_reaction(%mod{} = projection, reaction_ctx) do
    coerce =
      with metadata = metadata_from_projection(projection) do
        &maybe_convert_builders_to_events(&1, metadata)
      end

    result = mod.get_reaction(projection, reaction_ctx)

    maybe_events =
      case maybe_events_from_result(result) do
        nil -> nil
        events -> coerce.(events)
      end
      |> case do
        [] -> nil
        events -> events
      end

    maybe_commands = maybe_commands_from_result(result)

    if events = maybe_events do
      Enum.each(events, fn
        %Event{} -> :ok
        event -> raise "Expected only Events from #{inspect(mod)}, got: #{inspect(event)}"
      end)
    end

    [events: maybe_events, commands: maybe_commands]
    |> Enum.filter(fn {_, maybe_list} -> maybe_list end)
    |> case do
      [] -> nil
      kv -> Map.new(kv)
    end
  end

  #########################################################
  # Sent Reactions
  #########################################################

  defp __sent_reactions_field__() do
    quote do
      @typep reaction_key() :: {event_name :: String.t(), trace_id :: term()}
      field :__sent_reactions__, MapSet.t(reaction_key()), default: MapSet.new()
    end
  end

  defp accumulate_sent_reactions() do
    quote do
      Module.register_attribute(__MODULE__, :__reactive_messages__, accumulate: true)
    end
  end

  defp before_compile_sent_reactions() do
    quote do
      for event_name <- @__reactive_messages__ do
        unquote(__MODULE__).__maybe_react__(event_name)
      end
    end
  end

  defmacro __maybe_react__(event_name) do
    quote do
      handle_event unquote(event_name), ctx do
        unquote(__MODULE__).reaction_sent(ctx.projection, unquote(event_name))
      end
    end
  end

  @doc """
  Used by the aggregator in a `handle_event` to keep track of which reactions have been sent.
  """
  def reaction_sent(projection, message_name) do
    reaction_key = {message_name, projection.__trace_id__}
    sent_reactions = MapSet.put(projection.__sent_reactions__, reaction_key)
    [__sent_reactions__: sent_reactions]
  end

  @doc """
  Used by the aggregator in a `defreaction` to check if a reaction has already been sent.
  """
  def validate_unsent(
        %_{__trace_id__: trace_id, __sent_reactions__: reactions} = _projection,
        message_name
      ) do
    reaction_key = {message_name, trace_id}

    if MapSet.member?(reactions, reaction_key) do
      {:error, "reaction already sent"}
    else
      :ok
    end
  end

  def register_reaction(event_name, env) do
    Module.put_attribute(env.module, :__reactive_messages__, event_name)
  end

  #########################################################
  # Metadata
  #########################################################

  defp metadata_from_projection(projection),
    do: metadata_from_projection(projection, projection.__trace_id__)

  defp metadata_from_projection(projection, trace_id) do
    fn offset ->
      projection
      |> Projection.next_metadata(offset)
      |> Keyword.put(:trace_id, trace_id)
    end
  end
end
