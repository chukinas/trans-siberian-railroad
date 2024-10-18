defmodule TransSiberianRailroad.Event do
  @moduledoc """
  Events are a type of message that describes what happened in a game.
  In other words, a collection of game events fully describes the state of a game.
  The game state can be 100% reconstructed from the events.

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
    field :sequence_number, non_neg_integer()
  end

  defimpl Inspect do
    import Inspect.Algebra

    def inspect(event, opts) do
      payload = Map.to_list(event.payload || %{})
      payload = [{:v, event.sequence_number} | payload]
      concat(["#Event.#{event.name}<", Inspect.List.inspect(payload, opts), ">"])
    end
  end

  def new(name, payload, metadata) do
    %__MODULE__{
      name: name,
      payload: payload,
      sequence_number: Keyword.fetch!(metadata, :sequence_number)
    }
  end

  def compare(event1, event2) do
    case event1.sequence_number - event2.sequence_number do
      n when n > 0 -> :gt
      n when n < 0 -> :lt
      _ -> :eq
    end
  end
end
