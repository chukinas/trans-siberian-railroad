# TODO rename to Main maybe?
defmodule TransSiberianRailroad.Aggregator.Overview do
  use TransSiberianRailroad.Aggregator
  # TODO rm this dep
  alias TransSiberianRailroad.Aggregator.Players
  alias TransSiberianRailroad.Messages

  @type t() :: map()

  @impl true
  def init(), do: %{player_count: 0}

  @impl true
  def put_version(overview, version) do
    Map.put(overview, :last_version, version)
  end

  #########################################################
  # REDUCERS (command handlers)
  #########################################################

  # TODO need to have a rejection command?
  defp handle_command(_game, "initialize_game", %{game_id: game_id}) do
    Messages.game_initialized(game_id, sequence_number: 0)
  end

  defp handle_command(overview, "start_game", payload) do
    # TODO use dot notation
    player_count = overview[:player_count] || 0
    %{player_id: player_id} = payload
    # TODO temp
    index = 999
    metadata = &[sequence_number: index + &1]

    if player_count in 3..5 do
      player_order = Enum.shuffle(1..player_count)
      phase_number = 1
      # TODO temp
      starting_bidder = hd(player_order)

      [
        Messages.auction_phase_started(phase_number, starting_bidder, metadata.(0)),
        Messages.game_started(player_id, player_order, metadata.(1))
      ]
    else
      Messages.game_not_started("Cannot start game with fewer than 2 players.", metadata.(0))
    end
  end

  #########################################################
  # REDUCERS (event handlers)
  #########################################################

  defp handle_event(snapshot, "game_initialized", %{game_id: game_id}) do
    snapshot
    |> Map.put(:game_id, game_id)
    |> Map.put(:players, [])
  end

  defp handle_event(snapshot, "player_added", %{player_id: player_id, player_name: player_name}) do
    # TODO rm this first statement
    overview = Map.update!(snapshot, :players, &Players.add(&1, player_id, player_name))
    # Keep this one
    Map.update!(overview, :player_count, &(&1 + 1))
  end
end
