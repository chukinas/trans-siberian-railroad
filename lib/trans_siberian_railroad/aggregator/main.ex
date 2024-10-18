defmodule TransSiberianRailroad.Aggregator.Main do
  use TransSiberianRailroad.Aggregator
  use TypedStruct
  alias TransSiberianRailroad.Messages
  alias TransSiberianRailroad.Metadata

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
    field :last_version, non_neg_integer()
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
    Messages.start_player_set(start_player, Metadata.from_aggregator(ctx.projection))
  end

  handle_command "set_player_order", ctx do
    # TODO validate
    player_order = ctx.payload.player_order
    Messages.player_order_set(player_order, Metadata.from_aggregator(ctx.projection))
  end

  handle_command "start_game", ctx do
    main = ctx.projection
    player_count = main.player_count
    metadata = &Metadata.from_aggregator(main, &1)

    if player_count in 3..5 do
      start_player = main.start_player || Enum.random(1..player_count)
      player_order = Enum.shuffle(1..player_count)
      phase_number = 1

      transfers =
        with do
          starting_money = Map.fetch!(@starting_money_by_player_count, player_count)

          player_order
          |> Map.new(&{&1, starting_money})
          |> Map.put(:bank, -(starting_money * player_count))
        end

      [
        # TODO metadata order is borked
        unless(main.start_player,
          do: Messages.start_player_set(start_player, metadata.(0))
        ),
        unless(main.player_order_set,
          do: Messages.player_order_set(player_order, metadata.(0))
        ),
        # TODO game_started no longer needs a starting money field?
        Messages.game_started(metadata.(2)),
        Messages.money_transferred(transfers, "starting money", metadata.(3)),
        Messages.auction_phase_started(phase_number, start_player, metadata.(4))
      ]
    else
      Messages.game_start_rejected("Cannot start game with fewer than 2 players.", metadata.(0))
    end
  end
end
