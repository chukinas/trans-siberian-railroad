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
  - Add Events module that wraps the list of events.
    It'd store e.g. the latest event index / vesion.
    It would replace the test helper functions like fetch_single_event!/2.
  """

  use TypedStruct

  typedstruct enforce: true do
    field :name, String.t()
    field :payload, nil | map(), default: nil
    field :version, pos_integer()
    field :trace_id, Ecto.UUID.t()
  end

  defimpl Inspect do
    import Inspect.Algebra

    def inspect(event, opts) do
      payload = Map.to_list(event.payload || %{})
      payload = [{:v, event.version} | payload]
      concat(["#Event.#{event.name}<", Inspect.List.inspect(payload, opts), ">"])
    end
  end

  def new(name, payload, metadata) do
    %__MODULE__{
      name: name,
      payload: payload,
      version: Keyword.fetch!(metadata, :version),
      trace_id:
        case Keyword.fetch!(metadata, :trace_id) do
          nil -> raise "No trace_id provided for event #{name}"
          trace_id -> trace_id
        end
    }
  end

  def compare(event1, event2) do
    case event1.version - event2.version do
      n when n > 0 -> :gt
      n when n < 0 -> :lt
      _ -> :eq
    end
  end
end
