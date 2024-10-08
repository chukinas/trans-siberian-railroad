defmodule TransSiberianRailroad.Aggregator.Overview do
  use TransSiberianRailroad.Aggregator
  # TODO rm this dep
  alias TransSiberianRailroad.Aggregator.Players
  alias TransSiberianRailroad.Statechart

  @type t() :: map()

  @impl true
  def init(), do: %{}

  @impl true
  def put_version(overview, version) do
    Map.put(overview, :last_version, version)
  end

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
    Map.update!(snapshot, :players, &Players.add(&1, player_id, player_name))
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
