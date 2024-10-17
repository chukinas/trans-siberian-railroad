# TODO Rename this module to something more sensible.
defmodule TransSiberianRailroad.Banana do
  @moduledoc """
  This is taking over for game.ex

  The idea is that this will store the commands, events, and aggregators.
  For each command, we pass each command into the list of aggregators.
  From that we get one or more events back.
  We play those events back into the aggregators.
  This might return more events.
  Rinse and repeat until no more events are generated.
  Then we do the same for the next command.

  For the time being I'm still not worrying about race conditions.
  The code is still simple enough that I know that each command will
  only be processed by a single aggregator.

  I don't know what to call this module yet,
  so it's getting one of my typically silly names to make it obvious that a rename's necessary.

  ## Notes

  There's a risk of infinite loops if the aggregators keep generating the same events,
  but they're not getting handled properly.
  """

  use TypedStruct
  alias TransSiberianRailroad.Command
  alias TransSiberianRailroad.Event

  typedstruct enforce: true do
    field :commands, [Command.t()], default: []
    field :events, [Event.t()], default: []

    field :aggregator_modules, [module()],
      default: [
        TransSiberianRailroad.Aggregator.Main,
        TransSiberianRailroad.Aggregator.Players,
        TransSiberianRailroad.Aggregator.Companies,
        TransSiberianRailroad.Aggregator.Auction
      ]
  end

  defimpl Inspect do
    def inspect(banana, opts) do
      events = banana.events

      with_projections =
        update_in(banana, [Access.key!(:aggregator_modules), Access.all()], & &1.project(events))

      Inspect.Map.inspect(with_projections, opts)
    end
  end

  #########################################################
  # CONSTRUCTORS
  #########################################################

  def init(), do: %__MODULE__{}

  #########################################################
  # REDUCERS
  #########################################################

  @spec handle_commands(t(), [Command.t()]) :: t()
  def handle_commands(banana \\ init(), commands) do
    commands
    |> List.flatten()
    |> Enum.reject(&is_nil/1)
    |> Enum.reduce(banana, &handle_command(&2, &1))
  end

  @spec handle_command(t(), Command.t()) :: t()
  def handle_command(banana, %Command{} = command) do
    new_events = Enum.flat_map(banana.aggregator_modules, & &1.strawberry(banana.events, command))

    banana
    |> Map.update!(:commands, &[command | &1])
    |> handle_events(new_events)
  end

  @spec handle_event(t(), Event.t()) :: t()
  def handle_event(banana, %Event{} = event) do
    handle_events(banana, [event])
  end

  def handle_events(banana, new_events) do
    # TODO make sure the events are sorted by sequence number and increment exactly by one.
    # TODO a lot more is needed here.
    update = fn events -> Enum.reduce(new_events, events, &[&1 | &2]) end

    banana
    |> Map.update!(:events, update)
    |> generate_further_events()
  end

  # After a command causes events to be generated,
  # we need to play those events back into the aggregators
  # and see if they generate more events.
  # Example: the Auction module emits a company_auction_started after seeing a auction_phase_started event
  def generate_further_events(banana) do
    events_from_projections =
      Enum.flat_map(banana.aggregator_modules, fn agg_module ->
        banana.events
        |> agg_module.project()
        |> agg_module.events_from_projection()
        |> List.wrap()
        |> Enum.reject(&is_nil/1)
        |> ensure_events(agg_module)
      end)

    if Enum.any?(events_from_projections) do
      banana
      |> Map.update!(:events, &(Enum.reverse(events_from_projections) ++ &1))
      |> generate_further_events()
    else
      banana
    end
  end

  #########################################################
  # CONVERTERS
  #########################################################

  # TODO This should be part of the Events module
  def get_last_event(%{events: events}) do
    case events do
      [] -> nil
      [event | _] -> event
    end
  end

  #########################################################
  # HELPERS
  #########################################################

  defp ensure_events(events, aggregator) do
    Enum.each(events, fn
      %Event{} -> :ok
      event -> raise "Expected only Events from #{aggregator}, got: #{inspect(event)}"
    end)

    events
  end
end
