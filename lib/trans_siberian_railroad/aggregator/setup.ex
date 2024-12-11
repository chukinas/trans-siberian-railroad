defmodule Tsr.Aggregator.Setup do
  @moduledoc """
  Initialize game, add players, set start player and player order, and start the game.
  """

  use Tsr.Aggregator

  #########################################################
  # PROJECTION
  #########################################################

  use Tsr.Projection

  aggregator_typedstruct do
    field :game_id, String.t()
    field :player_count, 0..5, default: 0
    field :start_player, 1..5
    field :player_order_set, boolean(), default: false
    field :start_auction_phase, boolean(), default: false
  end

  #########################################################
  # Initialization
  #########################################################

  handle_command "initialize_game", ctx do
    %{game_id: game_id} = ctx.payload

    if ctx.projection.game_id do
      reason = "Game already initialized"
      event_builder("game_initialization_rejected", game_id: game_id, reason: reason)
    else
      event_builder("game_initialized", game_id: game_id)
    end
  end

  handle_event "game_initialized", ctx do
    [game_id: ctx.payload.game_id]
  end

  #########################################################
  # Adding Players
  #########################################################

  handle_command "add_player", ctx do
    %{player_name: player_name} = ctx.payload
    projection = ctx.projection
    player = projection.player_count + 1
    reject = &event_builder("player_rejected", player_name: player_name, reason: &1)

    cond do
      projection.player_order_set -> reject.("player order already set")
      player > 5 -> reject.("There are already 5 players")
      true -> event_builder("player_added", player: player, player_name: player_name)
    end
  end

  handle_event "player_added", ctx do
    new_player_count = ctx.projection.player_count + 1
    [player_count: new_player_count]
  end

  #########################################################
  # Start Player
  #########################################################

  handle_command "set_start_player", ctx do
    start_player = ctx.payload.player
    event_builder("start_player_set", start_player: start_player)
  end

  handle_event("start_player_set", ctx, do: [start_player: ctx.payload.start_player])

  #########################################################
  # Player Order
  #########################################################

  handle_command "set_player_order", ctx do
    player_order = ctx.payload.player_order
    event_builder("player_order_set", player_order: player_order)
  end

  handle_event("player_order_set", _ctx, do: [player_order_set: true])

  #########################################################
  # Game Start
  #########################################################

  handle_command "start_game", ctx do
    main = ctx.projection
    player_count = main.player_count

    if player_count in 3..5 do
      players = Enum.to_list(1..player_count)

      [
        unless main.start_player do
          event_builder("start_player_set", start_player: Enum.random(players))
        end,
        unless main.player_order_set do
          event_builder("player_order_set", player_order: Enum.shuffle(players))
        end,
        event_builder("game_started", players: players)
      ]
      |> Enum.filter(&is_function/1)
    else
      event_builder("game_start_rejected", reason: "Cannot start game with fewer than 2 players")
    end
  end

  handle_event("game_started", _ctx, do: [start_auction_phase: true])

  defreaction maybe_start_auction_phase(reaction_ctx) do
    if reaction_ctx.projection.start_auction_phase do
      ReactionCtx.command_if_unsent(reaction_ctx, "start_auction_phase", phase: 1)
    end
  end

  handle_event "auction_phase_started", _ctx do
    [start_auction_phase: false]
  end
end
