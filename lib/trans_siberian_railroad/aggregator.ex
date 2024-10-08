defmodule TransSiberianRailroad.Aggregator do
  @moduledoc """
  """

  alias TransSiberianRailroad.Event

  defmacro __using__(_) do
    quote do
      @mod TransSiberianRailroad.Aggregator
      @behaviour @mod
      @before_compile @mod

      @spec project(TransSiberianRailroad.Event.t()) :: t()
      def project(events) do
        {projection, _} = @mod.__state__(events, &init/0, &put_version/2, &handle_event/3)
        projection
      end

      # TODO this is getting kinda out of date
      @spec state(TransSiberianRailroad.Event.t()) :: {t(), [TransSiberianRailroad.Event.t()]}
      def state(events) do
        @mod.__state__(events, &init/0, &put_version/2, &handle_event/3)
      end

      # TODO this is too much injected code. Extract
      def strawberry(events, %TransSiberianRailroad.Command{name: command_name, payload: payload}) do
        new_events =
          events
          |> project()
          |> handle_command(command_name, payload)
          |> List.wrap()

        # TODO temp ensure all these are actual events
        for event <- new_events do
          case event do
            %Event{} -> :ok
            _ -> raise "Expected an Event, got: #{inspect(event)}"
          end
        end

        new_events
      end
    end
  end

  @type agg() :: term()

  @callback init() :: agg()
  @callback put_version(agg(), non_neg_integer()) :: agg()

  def __state__(events, init_fn, put_version_fn, handle_event_fn) do
    # TODO this should be part of the Events module
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

  defmacro __before_compile__(_) do
    quote do
      # Fallbacks
      def events_from_projection(_projection), do: nil
      defp handle_command(_projection, _unhandled_command_name, _unhandled_payload), do: nil
      defp handle_event(projection, _unhandled_event_name, _unhandled_payload), do: projection
    end
  end
end
