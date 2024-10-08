defmodule TransSiberianRailroad.Game do
  @moduledoc """
  This is the highest-level data structure for managing a game of Trans-Siberian Railroad.
  It tracks the current game state (e.g. rails build, players' money and stocks, etc.),
  as well as the events (commands and events) that have occurred in the game.

  The game state is a snapshot of the game at a particular point in time.
  It's the events that are the true source of truth for the game,
  and the game state is derived from them.
  """

  use TypedStruct
  # require Logger
  alias TransSiberianRailroad.Aggregator.Auction
  alias TransSiberianRailroad.Aggregator.Overview
  alias TransSiberianRailroad.Command
  alias TransSiberianRailroad.Event
  alias TransSiberianRailroad.Events
  alias TransSiberianRailroad.Messages
  alias TransSiberianRailroad.RailCompany

  typedstruct enforce: true do
    # TODO replace arbitrary map with struct
    field :snapshot, map(), default: %{}
    field :auction, Auction.t(), default: Auction.init()
    field :commands, [Command.t()], default: []
    # the head is the latest processed event
    field :events, [Event.t()], default: []
  end

  # @spec new() :: t()
  def new(), do: %__MODULE__{}

  # Take an incoming command,
  # queue up one or more resulting events,
  # then process the entire event queue, updating the game state each time.
  def handle_command(%__MODULE__{} = game, %Command{} = command) do
    game = %__MODULE__{game | commands: [command | game.commands]}

    events =
      do_handle_command(game, command.name, command.payload)
      |> List.wrap()

    Enum.reduce(events, game, &handle_event(&2, &1))
  end

  defp do_handle_command(_game, "initialize_game", %{game_id: game_id}) do
    Messages.game_initialized(game_id, sequence_number: 0)
  end

  defp do_handle_command(game, "add_player", %{player_name: player_name}) do
    # TODO outsource to a Players module?
    player_id = length(game.snapshot.players) + 1
    metadata = [sequence_number: Events.next_sequence_number(game.events)]

    if player_id <= 5 do
      Messages.player_added(player_id, player_name, metadata)
    else
      Messages.player_rejected(
        "'#{player_name}' cannot join the game. There are already 5 players.",
        metadata
      )
    end
  end

  defp do_handle_command(game, "start_game", %{player_id: player_id}) do
    player_count = length(game.snapshot.players)
    index = Events.next_sequence_number(game.events)
    metadata = &[sequence_number: index + &1]

    if player_count in 3..5 do
      player_order = Enum.shuffle(1..player_count)
      current_bidder = hd(player_order)

      [
        Messages.game_started(player_id, player_order, metadata.(0)),
        Messages.auction_started(current_bidder, RailCompany.phase_1_ids(), metadata.(1))
      ]
    else
      Messages.game_not_started("Cannot start game with fewer than 2 players.", metadata.(0))
    end
  end

  # TODO what should happen instead if that each command is passed to each handler,
  # Each of which has the opportunity to hand back one or more events.
  defp do_handle_command(game, command_name, payload) do
    {auction, _new_events} = Auction.state(game.events)

    Auction.handle_command(auction, command_name, payload)
  end

  defp handle_event(%__MODULE__{} = game, %Event{} = event) do
    snapshot = Overview.handle_event(game.snapshot, event.name, event.payload)
    auction = Auction.handle_event(game.auction, event.name, event.payload)
    %__MODULE__{game | snapshot: snapshot, auction: auction, events: [event | game.events]}
  end
end
