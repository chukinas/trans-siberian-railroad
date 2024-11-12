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
  require Logger
  alias TransSiberianRailroad.Aggregator
  alias TransSiberianRailroad.Command
  alias TransSiberianRailroad.Event
  alias TransSiberianRailroad.Projection

  @aggregators [
    TransSiberianRailroad.Aggregator.Setup,
    TransSiberianRailroad.Aggregator.AuctionPhase,
    TransSiberianRailroad.Aggregator.CompanyAuction,
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

    # arbitrary data used in unit tests
    field :__test__, map(), default: %{}
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
      Logger.warning("Expected #{inspect(event)} to have a version of #{expected_next_version}")
    end

    result = Enum.map(game.aggregators, &Projection.project_event(&1, event))
    aggregators = Enum.map(result, &elem(&1, 1))

    changed_aggs =
      Enum.flat_map(result, fn
        {:modified, agg} -> [agg]
        {:unchanged, _} -> []
      end)

    Logger.debug("""
    EVENT #{event.name}
    event: #{inspect(event)}
    updated aggs: #{inspect(changed_aggs, width: 120, pretty: true)}
    """)

    %__MODULE__{
      game
      | event_queue: event_queue,
        events: [event | game.events],
        events_version: event_version,
        aggregators: aggregators,
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

    result =
      Enum.find_value(game.aggregators, fn agg ->
        if reaction = Aggregator.get_reaction(agg, reaction_ctx) do
          {agg, reaction}
        end
      end)

    case result do
      nil ->
        %__MODULE__{game | last_reactions_version: version}

      {agg, reactions} ->
        # event: #{inspect(event)}
        # updated aggs: #{inspect(changed_aggs, width: 120, pretty: true)}
        Logger.debug("""
        REACTIONS
        aggregator: #{inspect(agg, width: 120, pretty: true)}
        reactions: #{inspect(reactions, width: 120, pretty: true)}
        """)

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

    {agg, maybe_events} =
      game.aggregators
      |> Enum.find_value(fn agg ->
        if events = Aggregator.maybe_events_from_command(agg, command) do
          {agg, events}
        end
      end)

    Logger.debug("""
    COMMAND #{command.name}
    command: #{inspect(command)}
    aggregator: #{inspect(agg, width: 50, pretty: true)}
    events: #{inspect(maybe_events)}
    """)

    event_queue =
      if events = maybe_events do
        events
      else
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

  def add_flag(game, flag) do
    fun = &[flag | &1]

    game
    |> update_in([Access.key!(:aggregators), Access.all(), Access.key!(:flags)], fun)
  end
end
