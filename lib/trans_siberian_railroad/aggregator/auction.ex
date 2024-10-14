defmodule TransSiberianRailroad.Aggregator.Auction do
  @moduledoc """
  This module handles all the events and commands related to the auctioning
  of rail companies to players.
  """

  use TypedStruct
  use TransSiberianRailroad.Aggregator
  require TransSiberianRailroad.RailCompany, as: Company
  alias TransSiberianRailroad.Aggregator.Players
  alias TransSiberianRailroad.Event
  alias TransSiberianRailroad.Messages
  alias TransSiberianRailroad.Metadata
  alias TransSiberianRailroad.Player

  #########################################################
  # PROJECTION
  #########################################################

  use TransSiberianRailroad.Projection

  typedstruct opaque: true do
    field :last_version, non_neg_integer()

    # game_started SETS true
    field :game_started, boolean(), default: false

    # game_started.player_order SETS
    field :player_order, [Player.id()]

    # money_transferred.transfers UPDATES
    # TODO testing property: a player's and company's balance may never be negative.
    field :player_money_balances, %{Player.id() => integer()}, default: %{}

    # auction_phase_started.phase_number SETS
    # auction_phase_ended CLEARS
    field :phase_number, 1..2

    # auction_phase_started.starting_bidder SETS
    # auction_phase_ended CLEARS
    field :phase_starting_bidder, 1..5

    # company_not_opened    INCREMENTS
    # company_opened        INCREMENTS
    # auction_phase_ended   SETS 0
    field :phase_count_company_auctions_ended, 0..4, default: 0

    # company_auction_started.company_id SETS
    # company_not_opened CLEARS
    # company_opened     CLEARS
    field :company, Company.id()

    # These are the players still in the bidding for the company's share.
    # As players pass, they are removed from this list.
    # The first player in the list is the current bidder.
    # company_auction_started.starting_bidder + :player_order SETS
    # company_bid MOVES the first player to end of list
    # company_passed REMOVES the first player
    # company_not_opened CLEARS
    # company_opened     CLEARS
    field :bidders, [Player.id()]
  end

  handle_event("player_order_set", ctx, do: [player_order: ctx.payload.player_order])
  handle_event("game_started", _ctx, do: [game_started: true])
  handle_event("company_opened", ctx, do: end_company_auction(ctx))
  handle_event("company_not_opened", ctx, do: end_company_auction(ctx))

  handle_event "money_transferred", ctx do
    player_money_balances = ctx.projection.player_money_balances
    transfers = ctx.payload.transfers

    new_player_money_balances =
      Enum.reduce(transfers, player_money_balances, fn
        {entity, amount}, balances when is_integer(entity) ->
          Map.update(balances, entity, amount, &(&1 + amount))

        _, balances ->
          balances
      end)

    [player_money_balances: new_player_money_balances]
  end

  handle_event "auction_phase_started", ctx do
    [phase_number: ctx.payload.phase_number, phase_starting_bidder: ctx.payload.starting_bidder]
  end

  handle_event "auction_phase_ended", _ctx do
    [phase_number: nil, phase_starting_bidder: nil, phase_count_company_auctions_ended: 0]
  end

  handle_event "company_auction_started", ctx do
    bidders =
      Players.player_order_once_around_the_table(
        ctx.projection.player_order,
        ctx.payload.starting_bidder
      )

    [company: ctx.payload.company, bidders: bidders]
  end

  handle_event "company_passed", ctx do
    bidders = Enum.drop(ctx.projection.bidders, 1)
    [bidders: bidders]
  end

  handle_event "company_bid", ctx do
    bidders =
      with [current_bidder | rest] <- ctx.projection.bidders do
        rest ++ [current_bidder]
      end

    [bidders: bidders]
  end

  defp end_company_auction(ctx) do
    [
      company: nil,
      bidders: nil,
      phase_count_company_auctions_ended: ctx.projection.phase_count_company_auctions_ended + 1
    ]
  end

  #########################################################
  # REDUCERS (command handlers)
  #########################################################

  @spec handle_command(t(), String.t(), map()) :: Event.t()
  defp handle_command(auction, "pass_on_company", payload) do
    %{player_id: player_id, company_id: company_id} = payload
    metadata = Metadata.from_aggregator(auction)
    maybe_current_bidder = get_current_bidder(auction)

    reject = fn reason ->
      Messages.company_pass_rejected(player_id, company_id, reason, metadata)
    end

    cond do
      !in_progress?(auction) ->
        reject.("no auction in progress")

      player_id != maybe_current_bidder ->
        reject.("It's player #{maybe_current_bidder}'s turn to bid on a company.")

      company_id != get_current_company(auction) ->
        reject.("The company you're trying to pass on isn't the one being auctioned.")

      true ->
        Messages.company_passed(player_id, company_id, metadata)
    end
  end

  # TODO the command (and event) names should be validated.
  defp handle_command(auction, "submit_bid", payload) do
    %{player_id: player_id, company_id: company_id, amount: amount} = payload

    player_money_balance = auction.player_money_balances[player_id] || 0

    maybe_rejection_reason =
      cond do
        player_money_balance < amount -> "insufficient funds"
        # TODO test
        amount < 8 -> "bid amount must be at least 8"
        # TODO it must be more than the previous bid
        true -> nil
      end

    # TODO test property: all events have incrementing sequence numbers
    # TODO validate all these fields
    case maybe_rejection_reason do
      nil ->
        [
          Messages.money_transferred(
            %{player_id => -amount, company_id => amount},
            "Player #{player_id} won the auction for #{company_id}'s opening share",
            Metadata.from_aggregator(auction, 0)
          ),
          Messages.company_bid(
            player_id,
            company_id,
            amount,
            Metadata.from_aggregator(auction, 1)
          )
        ]

      reason ->
        Messages.bid_rejected(
          player_id,
          company_id,
          amount,
          reason,
          Metadata.from_aggregator(auction)
        )
    end
  end

  #########################################################
  # CONVERTERS (projection -> events)
  #########################################################

  def events_from_projection(auction) do
    [
      &maybe_start_company_auction/1,
      &maybe_not_open_company/1,
      &maybe_end_auction_phase/1
    ]
    |> Enum.find_value(& &1.(auction))
  end

  defp maybe_start_company_auction(%__MODULE__{} = auction) do
    phase_number = auction.phase_number

    if !!phase_number and !auction.company do
      starting_bidder =
        case auction.phase_count_company_auctions_ended do
          _ -> auction.phase_starting_bidder
        end

      Company.ids(phase_number)
      |> Enum.drop(auction.phase_count_company_auctions_ended)
      |> case do
        [] ->
          nil

        [next_company | _] ->
          metadata = Metadata.from_aggregator(auction)
          Messages.company_auction_started(starting_bidder, next_company, metadata)
      end
    end
  end

  defp maybe_not_open_company(auction) do
    with {:ok, company} <- fetch_company(auction),
         true <- all_players_passed_on_company?(auction) do
      metadata = Metadata.from_aggregator(auction)
      Messages.company_not_opened(company, metadata)
    else
      _ -> nil
    end
  end

  defp maybe_end_auction_phase(%__MODULE__{} = auction) do
    if auction.phase_count_company_auctions_ended == 4 do
      metadata = Metadata.from_aggregator(auction)
      Messages.auction_phase_ended(auction.phase_number, metadata)
    end
  end

  #########################################################
  # CONVERTERS
  #########################################################

  defp all_players_passed_on_company?(%__MODULE__{bidders: bidders}) do
    bidders == []
  end

  def in_progress?(auction) do
    !!auction.phase_number
  end

  def fetch_current_bidder(auction) do
    case get_current_bidder(auction) do
      nil -> :error
      current_bidder -> {:ok, current_bidder}
    end
  end

  def get_current_bidder(auction) do
    case auction.bidders do
      [current_bidder | _] -> current_bidder
      _ -> nil
    end
  end

  defp fetch_company(auction) do
    maybe_company = auction.company

    if Company.is_id(maybe_company) do
      {:ok, maybe_company}
    else
      :error
    end
  end

  def get_current_company(auction) do
    auction.company
  end
end
