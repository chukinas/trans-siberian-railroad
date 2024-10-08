# TODO rename to Main maybe?
defmodule TransSiberianRailroad.Aggregator.Overview do
  use TransSiberianRailroad.Aggregator
  # TODO rm this dep
  alias TransSiberianRailroad.Aggregator.Players
  alias TransSiberianRailroad.Messages
  alias TransSiberianRailroad.RailCompany
  alias TransSiberianRailroad.Statechart

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
      current_bidder = hd(player_order)

      [
        Messages.game_started(player_id, player_order, metadata.(0)),
        Messages.auction_started(current_bidder, RailCompany.phase_1_ids(), metadata.(1))
      ]
    else
      Messages.game_not_started("Cannot start game with fewer than 2 players.", metadata.(0))
    end
  end

  defp handle_command(_overview, _unhandled_command_name, _unhandled_payload), do: nil

  #########################################################
  # REDUCERS (event handlers)
  #########################################################

  @impl true
  def handle_event(overview, event_name, payload) do
    update_snapshot(overview, event_name, payload)
  end

  defp update_snapshot(snapshot, "game_initialized", %{game_id: game_id}) do
    snapshot
    |> Map.put(:statechart, Statechart.new())
    |> Map.put(:game_id, game_id)
    |> Map.put(:players, [])
  end

  defp update_snapshot(snapshot, "player_added", %{player_id: player_id, player_name: player_name}) do
    # TODO rm this first statement
    overview = Map.update!(snapshot, :players, &Players.add(&1, player_id, player_name))
    # Keep this one
    Map.update!(overview, :player_count, &(&1 + 1))
  end

  defp update_snapshot(
         snapshot,
         "game_started",
         %{player_id: _, player_order: player_order} = payload
       )
       when map_size(payload) == 3 do
    first_player_id = hd(player_order)

    snapshot
    |> Map.update!(:statechart, &Statechart.start_game(&1, first_player_id))
  end

  defp update_snapshot(snapshot, "game_ended", _payload) do
    Map.update!(snapshot, :statechart, &Statechart.end_game/1)
  end

  defp update_snapshot(snapshot, _unhandled_message_name, _unhandled_payload) do
    # Logger.warning("#{inspect(__MODULE__)} unhandled event: #{unhandled_message_name}")
    snapshot
  end
end
