defmodule TransSiberianRailroad.Game do
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
  alias TransSiberianRailroad.Aggregator
  alias TransSiberianRailroad.Command
  alias TransSiberianRailroad.Event
  alias TransSiberianRailroad.Projection

  typedstruct enforce: true do
    field :commands, [Command.t()], default: []
    field :events, [Event.t()], default: []

    field :aggregators, [term()],
      default:
        Enum.map(
          [
            TransSiberianRailroad.Aggregator.Main,
            TransSiberianRailroad.Aggregator.Players,
            TransSiberianRailroad.Aggregator.Auction
          ],
          &Projection.project/1
        )
  end

  #########################################################
  # CONSTRUCTORS
  #########################################################

  def init() do
    %__MODULE__{}
  end

  #########################################################
  # REDUCERS
  #########################################################

  @spec handle_commands(t(), [Command.t()]) :: t()
  def handle_commands(game \\ init(), commands) do
    commands
    |> List.flatten()
    |> Enum.reject(&is_nil/1)
    |> Enum.reduce(game, &handle_one_command(&2, &1))
  end

  @spec handle_one_command(t(), Command.t()) :: t()
  def handle_one_command(game, %Command{} = command) do
    new_events = Enum.flat_map(game.aggregators, &Aggregator.handle_one_command(&1, command))

    game
    |> Map.update!(:commands, &[command | &1])
    |> handle_events(new_events)
  end

  @spec handle_event(t(), Event.t()) :: t()
  def handle_event(game, %Event{} = event) do
    handle_events(game, [event])
  end

  def handle_events(game, new_events) do
    Enum.reduce(new_events, game, &update_with_new_event(&2, &1))
    |> react()
  end

  # After a command causes events to be generated,
  # we need to play those events back into the aggregators
  # and see if they generate more events.
  # Example: the Auction module emits a company_auction_started after seeing a auction_phase_started event
  defp react(game) do
    new_events = Enum.flat_map(game.aggregators, &Aggregator.reactions(&1))
    game = Enum.reduce(new_events, game, &update_with_new_event(&2, &1))

    if Enum.any?(new_events) do
      react(game)
    else
      game
    end
  end

  # Update each aggregator and push the event on the events list
  defp update_with_new_event(game, %Event{} = event) do
    current_version =
      case game.events do
        [] -> 0
        [last_event | _] -> last_event.version
      end

    expected_next_version = current_version + 1

    if event.version == expected_next_version do
      :ok
    else
      require Logger

      Logger.warning("Expected #{inspect(event)} to have a version of #{expected_next_version}")
    end

    game
    |> Map.update!(:events, &[event | &1])
    |> update_in(
      [Access.key!(:aggregators), Access.all()],
      &Projection.handle_one_event(&1, event)
    )
  end
end
