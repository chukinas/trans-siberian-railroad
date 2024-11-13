defmodule TransSiberianRailroad.Event do
  @moduledoc """
  Events are a type of message that describes what happened in a game.
  In other words, a collection of game events fully describes the state of a game.
  The game state can be 100% reconstructed from the events.

  The version (number) is a one-indexed number (`t:pos_integer/0`) that represents the order in which the events were created.
  [Aggregators](`TransSiberianRailroad.Aggregator`) start off with a version though of 0 so we're always working with non-negative integers.

  ## Notes
  - Add a trace_id to the struct.
    Since events are typically (always?) created in response to a command,
    it would be useful to have a trace_id that links the event back to the command that caused it.
  - Give every event a timestamp.
  - Give every event a sequence number.
  - Add a macro that generates the event functions.
  - Enable and force marking each event with the module that's responsible for creating it.
    For each event, there should be exactly one such module.
  - How do I handle events that need to generate other events?
    Do the cascading events get created directly or do they
    need to have a command created first?
  """

  use TypedStruct
  require TransSiberianRailroad.Metadata, as: Metadata
  alias TransSiberianRailroad.Event

  typedstruct enforce: true do
    field :name, String.t()
    field :payload, map()
    field :id, Ecto.UUID.t()
    field :trace_id, Ecto.UUID.t()

    # This increments by one for each event.
    field :version, pos_integer()

    # This is only ever set by the Game module,
    # when a command or event is moved from its queue to its history.
    # It's used primarily for debugging,
    # to sort a single list of commands and events.
    field :global_version, pos_integer(), enforce: false
  end

  defmacro __using__(_) do
    quote do
      #   import unquote(__MODULE__)
      #   Module.register_attribute(__MODULE__, :__command_names__, accumulate: true)
      @before_compile unquote(__MODULE__)
      import unquote(__MODULE__)
      Module.register_attribute(__MODULE__, :event_names, accumulate: true)
    end
  end

  defmacro event(fields) do
    name =
      with {name, _arity} = __CALLER__.function do
        to_string(name)
      end

    Module.put_attribute(__CALLER__.module, :event_names, name)

    quote do
      name = unquote(name)
      payload = Map.new(unquote(fields))
      metadata = var!(metadata)
      TransSiberianRailroad.Event.new(name, payload, metadata)
    end
  end

  defmacro simple_event(name) do
    quote do
      Module.put_attribute(__MODULE__, :event_names, unquote(to_string(name)))

      def unquote(name)(metadata) do
        TransSiberianRailroad.Event.new(to_string(unquote(name)), %{}, metadata)
      end
    end
  end

  defmacro __before_compile__(_env) do
    quote do
      def event_names(), do: @event_names
    end
  end

  defimpl Inspect do
    import Inspect.Algebra

    def inspect(event, opts) do
      payload = Map.to_list(event.payload || %{})
      # digits = Map.get(opts, :__game_digits__, 0)
      # version = event.version |> to_string() |> String.pad_leading(digits, "0")
      short_id = String.slice(event.id, 0, 4)
      concat(["#Event.#{short_id}.#{event.name}", Inspect.List.inspect(payload, opts)])
    end
  end

  #########################################################
  # Constructors
  #########################################################

  def new(name, payload, metadata) when Metadata.is(metadata) do
    %__MODULE__{
      name: name,
      payload: payload,
      version: Keyword.fetch!(metadata, :version),
      id: metadata[:id] || Ecto.UUID.generate(),
      trace_id:
        case Keyword.fetch!(metadata, :trace_id) do
          nil -> raise "No trace_id provided for event #{name}"
          trace_id -> trace_id
        end
    }
  end

  #########################################################
  # Compare
  #########################################################

  def compare(event1, event2) do
    case event1.version - event2.version do
      n when n > 0 -> :gt
      n when n < 0 -> :lt
      _ -> :eq
    end
  end

  #########################################################
  # Converters
  #########################################################

  def await?(%__MODULE__{name: "awaiting_" <> _}), do: true
  def await?(_), do: false

  def version_gt?(%__MODULE__{version: version}, value), do: version > value

  #########################################################
  # Helpers
  #########################################################

  @doc """
  It's a common pattern for command handlers and reactions to return
  events in one of four forms:
  - a single event
  - an arity-1 function that converts a metadata to an event
  - a list of one of the above two

  This function takes one of the above and returns a list of events.
  """
  @type event_or_function() :: Event.t() | (Metadata.t() -> Event.t())
  @type metadata_from_offset() :: (offset :: non_neg_integer() -> Metadata.t())
  @spec coerce_to_events([event_or_function()], metadata_from_offset()) :: [Event.t()]
  def coerce_to_events(events_or_functions, metadata_from_index) do
    events_or_functions
    |> List.wrap()
    |> case do
      [fun | _] = events_or_functions when is_function(fun, 1) ->
        events_or_functions
        |> Enum.with_index()
        |> Enum.map(fn {build_msg, idx} -> build_msg.(metadata_from_index.(idx)) end)

      events ->
        events
    end
  end
end
