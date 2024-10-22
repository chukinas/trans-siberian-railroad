defmodule TransSiberianRailroad.Aggregator.PlayerTurn do
  @moduledoc """
  TODO
  """

  use TransSiberianRailroad.Aggregator
  use TransSiberianRailroad.Projection
  alias TransSiberianRailroad.Messages

  #########################################################
  # PROJECTION
  #########################################################

  typedstruct opaque: true do
    version_field()

    field :state_machine, [{:atom, Keyword.t()}],
      default: [awaiting_end_of_first_auction_phase: [start_player: nil]]
  end

  #########################################################
  # Listening for Start Player
  #########################################################

  handle_event "start_player_set", ctx do
    %{start_player: start_player} = ctx.payload

    state_machine =
      put_in(
        ctx.projection.state_machine,
        [:awaiting_end_of_first_auction_phase, :start_player],
        start_player
      )

    [state_machine: state_machine]
  end

  handle_event "player_won_company_auction", ctx do
    %{auction_winner: auction_winner} = ctx.payload

    state_machine =
      put_in(
        ctx.projection.state_machine,
        [:awaiting_end_of_first_auction_phase, :start_player],
        auction_winner
      )

    [state_machine: state_machine]
  end

  #########################################################
  # Player Turn Phase 1
  #########################################################

  handle_event "auction_phase_ended", ctx do
    state_machine = [{:first_auction_ended, true} | ctx.projection.state_machine]
    [state_machine: state_machine]
  end

  defreaction maybe_start_player_turn(projection) do
    state_machine = projection.state_machine
    current_player = state_machine[:awaiting_end_of_first_auction_phase][:start_player]

    case state_machine do
      [{:first_auction_ended, _} | _] ->
        metadata = Projection.next_metadata(projection)
        Messages.player_turn_started(current_player, metadata)

      _ ->
        nil
    end
  end

  handle_event "player_turn_started", ctx do
    %{player: player} = ctx.payload

    state_machine =
      put_in(
        ctx.projection.state_machine,
        [:awaiting_end_of_first_auction_phase, :start_player],
        player
      )

    state_machine = [{:player_turn, true} | state_machine]
    [state_machine: state_machine]
  end

  #########################################################
  # Pass
  #########################################################

  handle_command "pass", ctx do
    %{passing_player: passing_player} = ctx.payload

    reason =
      case Keyword.fetch(ctx.projection.state_machine, :player_turn) do
        {:ok, _} ->
          if passing_player !=
               ctx.projection.state_machine[:awaiting_end_of_first_auction_phase][:start_player] do
            "incorrect player"
          end

        :error ->
          "not a player turn"
      end

    if reason do
      Messages.pass_rejected(passing_player, reason, ctx.metadata.(0))
    else
      [
        Messages.passed(passing_player, ctx.metadata.(0)),
        Messages.end_of_turn_sequence_started(ctx.metadata.(1))
      ]
    end
  end
end
