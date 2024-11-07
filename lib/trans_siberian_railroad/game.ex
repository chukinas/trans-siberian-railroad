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

  @aggregators [
    TransSiberianRailroad.Aggregator.Setup,
    TransSiberianRailroad.Aggregator.Auction,
    TransSiberianRailroad.Aggregator.Orchestration,
    TransSiberianRailroad.Aggregator.PlayerTurn,
    TransSiberianRailroad.Aggregator.TimingTrack,
    TransSiberianRailroad.Aggregator.Interturn,
    TransSiberianRailroad.Aggregator.IncomeTrack,
    TransSiberianRailroad.Aggregator.StockCertificates,
    TransSiberianRailroad.Aggregator.StockValue
  ]

  typedstruct enforce: true do
    field :event_queue, [Event.t()], default: []
    field :events, [Event.t()], default: []
    field :events_version, integer(), default: 0

    field :last_reactions_version, integer(), default: -1
    field :global_version, non_neg_integer(), default: 0

    field :command_queue, [Command.t()], default: []
    field :commands, [Command.t()], default: []

    field :aggregators, [term()], default: Enum.map(@aggregators, &Projection.project/1)
  end

  #########################################################
  # CONSTRUCTORS
  #########################################################

  def new() do
    %__MODULE__{}
  end

  #########################################################
  # REDUCERS
  #########################################################

  def queue_command(game, %Command{} = command) do
    # Of course, inserting elements at the end of a list is inefficient,
    # but in production, it will be rare that a command gets queued when there are already commands in the queue.
    Map.update!(game, :command_queue, &List.insert_at(&1, -1, command))
  end

  # EVENT QUEUE
  def execute(%__MODULE__{event_queue: [event | event_queue]} = game) do
    global_version = game.global_version + 1
    event = Map.replace!(event, :global_version, global_version)
    event_version = event.version
    current_version = game.events_version
    expected_next_version = current_version + 1

    if event_version == expected_next_version do
      :ok
    else
      require Logger
      Logger.warning("Expected #{inspect(event)} to have a version of #{expected_next_version}")
    end

    %__MODULE__{
      game
      | event_queue: event_queue,
        events: [event | game.events],
        events_version: event_version,
        aggregators: Enum.map(game.aggregators, &Projection.handle_one_event(&1, event)),
        global_version: global_version
    }
    |> execute()
  end

  # REACTIONS
  def execute(
        %__MODULE__{events_version: version, last_reactions_version: last_reactions_version} =
          game
      )
      when last_reactions_version < version do
    ids =
      [game.events, game.event_queue, game.commands, game.command_queue]
      |> Stream.concat()
      |> Stream.map(& &1.id)
      |> MapSet.new()

    unsent? = fn %{id: id} -> !MapSet.member?(ids, id) end

    if_unsent = fn message ->
      case {unsent?.(message), message} do
        {true, %Command{}} -> %{commands: [message]}
        {true, %Event{}} -> %{events: [message]}
        _ -> nil
      end
    end

    reaction_ctx = %{sent_ids: ids, unsent?: unsent?, if_unsent: if_unsent}

    case Enum.find_value(game.aggregators, &Aggregator.get_reaction(&1, reaction_ctx)) do
      nil ->
        %__MODULE__{game | last_reactions_version: version}

      reactions ->
        event_queue = Map.get(reactions, :events, [])

        %__MODULE__{
          game
          | event_queue: event_queue,
            command_queue: game.command_queue ++ Map.get(reactions, :commands, [])
        }
    end
    |> execute()
  end

  # COMMAND QUEUE
  def execute(%__MODULE__{command_queue: [command | command_queue]} = game) do
    global_version = game.global_version + 1
    command = Map.replace!(command, :global_version, global_version)

    event_queue =
      if events =
           Enum.find_value(game.aggregators, &Aggregator.maybe_events_from_command(&1, command)) do
        events
      else
        require Logger
        Logger.warning("#{inspect(command)} did not result in any events")
        []
      end

    %__MODULE__{
      game
      | command_queue: command_queue,
        commands: [command | game.commands],
        event_queue: event_queue,
        global_version: global_version
    }
    |> execute()
  end

  # STEP 4: Fallback
  def execute(game) do
    game
  end

  # public for testing purposes only!
  def __queue_event__(game, %Event{} = event) do
    Map.update!(game, :event_queue, &List.insert_at(&1, -1, event))
  end
end
