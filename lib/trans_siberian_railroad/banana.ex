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
  """

  alias TransSiberianRailroad.Command

  @type t() :: map()

  #########################################################
  # CONSTRUCTORS
  #########################################################

  def init() do
    %{
      commands: [],
      events: [],
      aggregator_modules: [
        TransSiberianRailroad.Aggregator.Overview,
        TransSiberianRailroad.Aggregator.Players,
        TransSiberianRailroad.Aggregator.Companies,
        TransSiberianRailroad.Aggregator.Auction
      ]
    }
  end

  #########################################################
  # REDUCERS
  #########################################################

  @spec handle_commands(t(), [Command.t()]) :: t()
  def handle_commands(banana \\ init(), commands) do
    commands
    |> List.flatten()
    |> Enum.reduce(banana, &handle_command(&2, &1))
  end

  @spec handle_command(t(), Command.t()) :: t()
  def handle_command(banana, command) do
    banana = Map.update!(banana, :commands, &[command | &1])
    new_events = Enum.flat_map(banana.aggregator_modules, & &1.strawberry(banana.events, command))

    events = Enum.reduce(new_events, banana.events, &[&1 | &2])

    # TODO make sure the events are sorted by sequence number and increment exactly by one.
    # TODO a lot more is needed here.
    Map.put(banana, :events, events)
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
end
