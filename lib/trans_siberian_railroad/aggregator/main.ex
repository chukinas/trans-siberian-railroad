defmodule TransSiberianRailroad.Aggregator.Main do
  use TransSiberianRailroad.Aggregator
  use TypedStruct
  alias TransSiberianRailroad.Messages
  alias TransSiberianRailroad.Metadata

  typedstruct do
    field :last_version, non_neg_integer()
    field :player_count, 0..5, default: 0
  end

  #########################################################
  # CONSTRUCTORS
  #########################################################

  @impl true
  def init(), do: %__MODULE__{}

  #########################################################
  # REDUCERS
  #########################################################

  @impl true
  def put_version(main, version) do
    %__MODULE__{main | last_version: version}
  end

  #########################################################
  # REDUCERS (command handlers)
  #########################################################

  defp handle_command(_main, "initialize_game", %{game_id: game_id}) do
    Messages.game_initialized(game_id, sequence_number: 0)
  end

  defp handle_command(main, "start_game", payload) do
    player_count = main.player_count
    %{player_id: player_who_requested_game_start} = payload
    metadata = &Metadata.from_aggregator(main, &1)

    if player_count in 3..5 do
      start_player = Enum.random(1..player_count)
      player_order = Enum.shuffle(1..player_count)
      phase_number = 1

      starting_money =
        case length(player_order) do
          3 -> 48
          4 -> 40
          5 -> 32
        end

      [
        Messages.start_player_selected(start_player, metadata.(0)),
        Messages.player_order_set(player_order, metadata.(1)),
        Messages.game_started(player_who_requested_game_start, starting_money, metadata.(2)),
        Messages.auction_phase_started(phase_number, start_player, metadata.(3))
      ]
    else
      Messages.game_not_started("Cannot start game with fewer than 2 players.", metadata.(0))
    end
  end

  #########################################################
  # REDUCERS (event handlers)
  #########################################################

  defp handle_event(main, "game_initialized", %{game_id: game_id}) do
    main
    |> Map.put(:game_id, game_id)
    |> Map.put(:players, [])
  end

  defp handle_event(main, "player_added", _payload) do
    Map.update!(main, :player_count, &(&1 + 1))
  end
end
