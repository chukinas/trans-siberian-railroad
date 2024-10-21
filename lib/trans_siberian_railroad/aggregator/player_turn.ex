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
  # Pass
  #########################################################

  handle_command "pass", ctx do
    %{passing_player: passing_player} = ctx.payload

    reason =
      case Keyword.fetch(ctx.projection.state_machine, :player_turn) do
        :error -> "not a player turn"
      end

    metadata = ctx.next_metadata
    Messages.pass_rejected(passing_player, reason, metadata)
  end
end
