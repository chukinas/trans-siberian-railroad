defmodule TransSiberianRailroad.Aggregator.Main do
  use TransSiberianRailroad.Aggregator
  use TypedStruct
  alias TransSiberianRailroad.Messages
  alias TransSiberianRailroad.Metadata

  #########################################################
  # PROJECTION
  #########################################################

  use TransSiberianRailroad.Projection

  typedstruct do
    field :last_version, non_neg_integer()
    field :game_id, String.t()
    field :player_count, 0..5, default: 0
  end

  handle_event("game_initialized", ctx, do: [game_id: ctx.payload.game_id])

  handle_event "player_added", ctx do
    new_player_count = ctx.projection.player_count + 1
    [player_count: new_player_count]
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

      transfers =
        player_order
        |> Map.new(&{&1, starting_money})
        |> Map.put(:bank, -(starting_money * player_count))

      [
        Messages.start_player_selected(start_player, metadata.(0)),
        Messages.player_order_set(player_order, metadata.(1)),
        # TODO game_started no longer needs a starting money field?
        Messages.game_started(player_who_requested_game_start, starting_money, metadata.(2)),
        Messages.money_transferred(transfers, "starting money", metadata.(3)),
        Messages.auction_phase_started(phase_number, start_player, metadata.(4))
      ]
    else
      Messages.game_not_started("Cannot start game with fewer than 2 players.", metadata.(0))
    end
  end
end
