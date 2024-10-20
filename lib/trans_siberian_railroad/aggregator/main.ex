defmodule TransSiberianRailroad.Aggregator.Main do
  # TODO moduledoc
  use TransSiberianRailroad.Aggregator
  use TypedStruct
  alias TransSiberianRailroad.Messages

  @starting_money_by_player_count %{
    3 => 48,
    4 => 40,
    5 => 32
  }

  #########################################################
  # PROJECTION
  #########################################################

  use TransSiberianRailroad.Projection

  typedstruct do
    version_field()
    field :game_id, String.t()
    field :player_count, 0..5, default: 0
    field :start_player, 1..5
    field :player_order_set, boolean(), default: false
    field :game_started, boolean(), default: false
  end

  handle_event("game_initialized", ctx, do: [game_id: ctx.payload.game_id])

  handle_event "player_added", ctx do
    new_player_count = ctx.projection.player_count + 1
    [player_count: new_player_count]
  end

  # TODO loop these
  handle_event("start_player_set", ctx, do: [start_player: ctx.payload.start_player])
  handle_event("player_order_set", _ctx, do: [player_order_set: true])
  handle_event("game_started", _ctx, do: [game_started: true])

  #########################################################
  # REDUCERS (command handlers)
  #########################################################

  handle_command "initialize_game", ctx do
    %{game_id: game_id} = ctx.payload
    # TODO this should be dynamic
    Messages.game_initialized(game_id, sequence_number: 0)
  end

  handle_command "set_start_player", ctx do
    # TODO validate
    start_player = ctx.payload.start_player
    Messages.start_player_set(start_player, Projection.next_metadata(ctx.projection))
  end

  handle_command "set_player_order", ctx do
    # TODO validate
    player_order = ctx.payload.player_order
    Messages.player_order_set(player_order, Projection.next_metadata(ctx.projection))
  end

  handle_command "start_game", ctx do
    main = ctx.projection
    player_count = main.player_count
    metadata = &Projection.next_metadata(main, &1)

    if player_count in 3..5 do
      player_ids = 1..player_count
      start_player = main.start_player || Enum.random(player_ids)
      phase_number = 1

      transfers =
        with do
          starting_money = Map.fetch!(@starting_money_by_player_count, player_count)

          player_ids
          |> Map.new(&{&1, starting_money})
          |> Map.put(:bank, -(starting_money * player_count))
        end

      [
        unless main.start_player do
          &Messages.start_player_set(start_player, &1)
        end,
        unless main.player_order_set do
          player_order = Enum.shuffle(player_ids)
          &Messages.player_order_set(player_order, &1)
        end,
        &Messages.game_started(&1),
        &Messages.money_transferred(transfers, "starting money", &1),
        &Messages.auction_phase_started(phase_number, start_player, &1)
      ]
      |> Enum.filter(&is_function/1)
      |> Enum.with_index()
      |> Enum.map(fn {build_msg, idx} -> build_msg.(metadata.(idx)) end)
    else
      Messages.game_start_rejected("Cannot start game with fewer than 2 players.", metadata.(0))
    end
  end
end
