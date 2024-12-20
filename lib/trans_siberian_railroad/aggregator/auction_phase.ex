defmodule Tsr.Aggregator.AuctionPhase do
  @moduledoc """
  This module orchestates the one or two auction phases of the game.

  It listens for `auction_phase_started` and emits `auction_phase_ended` event when done.
  In between those two events, it decides which `company_auction_started` to emit.

  There are two auction phases in the game:
  - in phase 1, we auction off the red, blue, green, and yellow companies
  - in phase 2, we auction off the black and white companies
  """

  use Tsr.Aggregator

  # invariant: all three fields are either all nil or all non-nil
  aggregator_typedstruct do
    field :phase_number, 1..2
    field :start_player, Constants.player()

    # default to nil
    # e: auction_phase_started: populate the list
    # r: if first el is :start, emit company_auction_started
    # e: company_auction_started: drop element
    # e: company_auction_ended: drop element
    # r: if empty list, emit auction_phase_ended
    # e: auction_phase_ended: set to nil
    field :next_steps, [{Constants.company(), :start | :end}]
  end

  defp drop_next_step(ctx, company, start_or_end) do
    next_steps =
      if next_steps = ctx.projection.next_steps do
        Enum.reject(next_steps, &(&1 == {company, start_or_end}))
      end

    [next_steps: next_steps]
  end

  #########################################################
  # Start auction phase
  #########################################################

  handle_event "auction_phase_started", ctx do
    %{phase: phase_number, start_player: start_player} = ctx.payload

    companies =
      case phase_number do
        1 -> Constants.companies() |> Enum.take(4)
        2 -> Constants.companies() |> Enum.drop(4)
      end

    next_steps =
      for company <- companies, start_or_end <- ~w/start end/a do
        {company, start_or_end}
      end

    [
      phase_number: phase_number,
      start_player: start_player,
      next_steps: next_steps
    ]
  end

  #########################################################
  # Start company auction
  #########################################################

  defreaction maybe_start_company_auction(%{projection: projection}) do
    case projection.next_steps do
      [{company, :start} | _] ->
        event_builder("company_auction_started",
          start_player: projection.start_player,
          company: company
        )

      _ ->
        nil
    end
  end

  handle_event "company_auction_started", ctx do
    drop_next_step(ctx, ctx.payload.company, :start)
  end

  #########################################################
  # Keep :start_player up to date
  #########################################################

  handle_event "player_won_company_auction", ctx do
    [start_player: ctx.payload.player]
  end

  #########################################################
  # Listen for "company_auction_ended"
  #########################################################

  handle_event "company_auction_ended", ctx do
    drop_next_step(ctx, ctx.payload.company, :end)
  end

  #########################################################
  # End auction phase
  #########################################################

  defreaction maybe_end_auction_phase(%{projection: projection}) do
    if [] == projection.next_steps do
      %{phase_number: phase, start_player: start_player} = projection
      event_builder("auction_phase_ended", phase: phase, start_player: start_player)
    end
  end

  handle_event "auction_phase_ended", _ctx do
    [
      phase_number: nil,
      next_steps: nil,
      start_player: nil
    ]
  end
end
