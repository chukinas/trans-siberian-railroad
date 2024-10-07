defmodule TransSiberianRailroad.Aggregator do
  @moduledoc """
  """

  alias TransSiberianRailroad.Event

  defmacro __using__(_) do
    quote do
      @mod TransSiberianRailroad.Aggregator
      @behaviour @mod

      @spec state(TransSiberianRailroad.Event.t()) :: {t(), [TransSiberianRailroad.Event.t()]}
      def state(events) do
        @mod.__state__(events, &init/0, &put_version/2, &handle_event/3)
      end
    end
  end

  @type agg() :: term()

  @callback init() :: agg()
  @callback put_version(agg(), non_neg_integer()) :: agg()
  @callback handle_event(any(), String.t(), payload :: map()) :: any()

  def __state__(events, init_fn, put_version_fn, handle_event_fn) do
    events = Event.sort(events)

    aggregator =
      Enum.reduce(events, init_fn.(), fn event, aggregator ->
        %Event{
          name: event_name,
          payload: payload,
          sequence_number: sequence_number
        } = event

        aggregator
        |> put_version_fn.(sequence_number)
        |> handle_event_fn.(event_name, payload)
      end)

    {aggregator, []}
  end
end
