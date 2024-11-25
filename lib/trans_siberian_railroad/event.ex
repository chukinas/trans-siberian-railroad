defmodule Tsr.Event do
  @moduledoc """
  Events are a type of message that describes what happened in a game.
  In other words, a collection of game events fully describes the state of a game.
  The game state can be 100% reconstructed from the events.

  The version (number) is a one-indexed number (`t:pos_integer/0`) that represents the order in which the events were created.
  [Aggregators](`Tsr.Aggregator`) start off with a version though of 0 so we're always working with non-negative integers.

  ## Notes
  - Give every event a timestamp.
  - Add a macro that generates the event functions.
  - Enable and force marking each event with the module that's responsible for creating it.
    For each event, there should be exactly one such module.
  """

  use TypedStruct
  require Tsr.Metadata, as: Metadata
  alias Tsr.Message

  #########################################################
  # Struct
  #########################################################

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

  def __new__(event_name, validated_payload, metadata) do
    metadata = Metadata.for_event(metadata, []) |> Map.new()

    %__MODULE__{
      id: metadata.id,
      name: event_name,
      payload: validated_payload,
      trace_id: metadata.trace_id,
      version: metadata.version
    }
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

  def compare(event1, event2) do
    case event1.version - event2.version do
      n when n > 0 -> :gt
      n when n < 0 -> :lt
      _ -> :eq
    end
  end

  def await?(%__MODULE__{name: "awaiting_" <> _}), do: true
  def await?(_), do: false

  def version_gt?(%__MODULE__{version: version}, value), do: version > value

  #########################################################
  # Metaprogramming
  #########################################################

  defmacro __using__(_) do
    quote do
      @before_compile unquote(__MODULE__)
      import unquote(__MODULE__)
      Module.register_attribute(__MODULE__, :__events__, accumulate: true)
    end
  end

  defmacro defevent(event_name, keys \\ []) do
    quote do
      if Enum.find(@__events__, &(elem(&1, 0) == unquote(event_name))) do
        raise """
        Event #{unquote(event_name)} has already been defined.
        """
      end

      @__events__ unquote({event_name, keys})
    end
  end

  defmacro __before_compile__(_env) do
    quote do
      @event_names_and_fields Map.new(@__events__)
      def event_builder(event_name, payload \\ %{}) do
        fields = Map.fetch!(@event_names_and_fields, event_name)
        payload = Message.validated_payload!(event_name, payload, fields)

        fn metadata ->
          unquote(__MODULE__).__new__(event_name, payload, metadata)
        end
      end

      @event_names Map.keys(@event_names_and_fields)
      def event_names() do
        @event_names
      end
    end
  end

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
  def coerce_to_events(events_or_functions, version, trace_id) do
    events_or_functions
    |> List.wrap()
    |> case do
      [fun | _] = events_or_functions when is_function(fun, 1) ->
        events_or_functions
        |> Enum.with_index()
        |> Enum.map(fn {build_msg, idx} ->
          Metadata.for_event(version: version + 1 + idx, trace_id: trace_id)
          |> build_msg.()
        end)

      events ->
        events
    end
  end
end
