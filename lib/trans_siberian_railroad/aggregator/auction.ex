defmodule TransSiberianRailroad.Aggregator.Auction do
  @moduledoc """
  This module handles all the events and commands related to the auctioning
  of rail companies to players.

  This aggregator waits for the `auction_phase_started` event to start the auction phase.
  But IT decides when to end the auction phase. It does this by looking at the state of the auction.
  When all companies have been auctioned off, it emits the `auction_phase_ended` event.

  There are two auction phases in the game:
  - in phase 1, we auction off the red, blue, green, and yellow companies
  - in phase 2, we auction off the black and white companies

  For each of these company auctions, players take turns bidding or passing on the company.
  It's the first company stock certificate that's up for bid.
  To bid, you have to bid at least 8 and more than any amount anyone else has bid on that company so far.
  Eventually, one of two things happens:
  - all players pass on the company. The company is removed from the game.
  - only one player is left. That player wins the company and pays the amount they bid for it. They get the company's stock certificate.
    The company is now "open".
  """

  use TransSiberianRailroad.Aggregator
  use TransSiberianRailroad.Projection
  require TransSiberianRailroad.Player, as: Player
  alias TransSiberianRailroad.Messages
  alias TransSiberianRailroad.Players
  alias TransSiberianRailroad.RailCompany, as: Company

  #########################################################
  # PROJECTION
  #########################################################

  aggregator_typedstruct do
    field :player_order, [Player.id()]
    field :player_money_balances, %{Player.id() => non_neg_integer()}, default: %{}

    # auction phase state
    field :phase_number, 1..2
    field :start_bidder, Player.id()
    field :remaining_companies, [Company.id()], default: []

    # current company
    field :current_company, Company.id()
    field :bidders, [{Player.id(), nil | non_neg_integer()}], default: []
    field :awaiting_stock_price, boolean(), default: false
  end

  @clear_company_auction [
    current_company: nil,
    bidders: [],
    awaiting_stock_price: false
  ]

  @clear_auction [
                   phase_number: nil,
                   remaining_companies: [],
                   start_bidder: nil
                 ] ++ @clear_company_auction

  #########################################################
  # event handlers not specific to the auction
  #########################################################

  handle_event "player_order_set", ctx do
    [player_order: ctx.payload.player_order]
  end

  handle_event "money_transferred", ctx do
    transfers = ctx.payload.transfers
    player_money_balances = ctx.projection.player_money_balances

    new_player_money_balances =
      Enum.reduce(transfers, player_money_balances, fn
        {entity, amount}, balances when Player.is_id(entity) ->
          Map.update(balances, entity, amount, &(&1 + amount))

        _, balances ->
          balances
      end)

    [player_money_balances: new_player_money_balances]
  end

  #########################################################
  # start an auction phase and company auctions
  #########################################################

  handle_event "auction_phase_started", ctx do
    %{phase_number: phase_number, start_bidder: start_bidder} = ctx.payload

    [
      # AUCTION PHASE STATE
      phase_number: phase_number,
      start_bidder: start_bidder,
      remaining_companies:
        case phase_number do
          1 -> ~w(red blue green yellow)a
          2 -> ~w(black white)a
        end
    ] ++ @clear_company_auction
  end

  defreaction maybe_start_company_auction(%__MODULE__{} = projection) do
    with :ok <- validate_in_between_company_auctions(projection),
         {:ok, next_company} <- fetch_next_company(projection),
         {:ok, start_bidder} <- fetch_start_bidder(projection) do
      &Messages.company_auction_started(start_bidder, next_company, &1)
    else
      _ -> nil
    end
  end

  handle_event "company_auction_started", ctx do
    %{start_bidder: start_bidder, company: company} = ctx.payload

    [
      # AUCTION PHASE STATE
      # :phase_number remains unchanged
      start_bidder: start_bidder,
      remaining_companies: Enum.reject(ctx.projection.remaining_companies, &(&1 == company)),

      # COMPANY AUCTION STATE
      current_company: company,
      bidders:
        ctx.projection.player_order
        |> Players.one_round(start_bidder)
        |> Enum.map(&{&1, nil}),
      awaiting_stock_price: false
    ]
  end

  #########################################################
  # awaiting
  #########################################################

  Aggregator.register_reaction("awaiting_bid_or_pass", __ENV__)

  defreaction maybe_awaiting_bid_or_pass(projection) do
    with :ok <- Aggregator.validate_unsent(projection, "awaiting_bid_or_pass"),
         :ok <- validate_bidding_in_progress(projection),
         {:ok, company} <- fetch_current_company(projection),
         {:ok, player} <- fetch_current_bidder(projection) do
      min_bid =
        case fetch_highest_bid(projection) do
          {:ok, amount} -> amount + 1
          {:error, _} -> 8
        end

      &Messages.awaiting_bid_or_pass(player, company, min_bid, &1)
    else
      _ -> nil
    end
  end

  #########################################################
  # handle players passing on a company
  #########################################################

  handle_command "pass_on_company", ctx do
    %{passing_player: passing_player, company: company} = ctx.payload
    projection = ctx.projection

    with :ok <- validate_auction_phase(projection),
         :ok <- validate_company_auction(projection),
         :ok <- validate_bidding_in_progress(projection),
         :ok <- validate_current_bidder(projection, passing_player),
         :ok <- validate_current_company(projection, company) do
      &Messages.company_passed(passing_player, company, &1)
    else
      {:error, reason} -> &Messages.company_pass_rejected(passing_player, company, reason, &1)
    end
  end

  handle_event "company_passed", ctx do
    %{passing_player: passing_player} = ctx.payload
    bidders = Enum.reject(ctx.projection.bidders, fn {player, _} -> player == passing_player end)
    [bidders: bidders]
  end

  defreaction maybe_all_players_passed_on_company(projection) do
    with :ok <- validate_no_bidders(projection),
         {:ok, company} <- fetch_current_company(projection) do
      &Messages.all_players_passed_on_company(company, &1)
    else
      _ -> nil
    end
  end

  handle_event "all_players_passed_on_company", _ctx do
    @clear_company_auction
  end

  #########################################################
  # handle players bidding on a company
  #########################################################

  handle_command "submit_bid", ctx do
    %{bidder: bidder, company: company, amount: amount} = ctx.payload
    projection = ctx.projection

    with :ok <- validate_auction_phase(projection),
         :ok <- validate_company_auction(projection),
         :ok <- validate_bidding_in_progress(projection),
         :ok <- validate_current_bidder(projection, bidder),
         :ok <- validate_current_company(projection, company),
         :ok <- validate_min_bid(amount),
         :ok <- validate_increasing_bid(projection, amount),
         :ok <- validate_balance(projection, bidder, amount) do
      &Messages.bid_submitted(bidder, company, amount, &1)
    else
      {:error, reason} -> &Messages.bid_rejected(bidder, company, amount, reason, &1)
    end
  end

  handle_event "bid_submitted", ctx do
    %{bidder: bidder, amount: amount} = ctx.payload

    [
      # CURRENT COMPANY STATE
      # :current_company remains unchanged
      bidders:
        with [{^bidder, _} | rest] = ctx.projection.bidders do
          rest ++ [{bidder, amount}]
        end,
      awaiting_stock_price: false
    ]
  end

  defreaction maybe_player_won_company_auction(projection) do
    with :ok <- validate_auction_phase(projection),
         false <- projection.awaiting_stock_price,
         :ok <- validate_company_auction(projection),
         {:ok, company} <- fetch_current_company(projection),
         {:ok, auction_winner} <- fetch_single_bidder(projection),
         {:ok, amount} <- fetch_highest_bid(projection) do
      reason = "company stock auctioned off"

      [
        &Messages.player_won_company_auction(auction_winner, company, amount, &1),
        &Messages.stock_certificates_transferred(company, company, auction_winner, 1, reason, &1),
        &Messages.money_transferred(%{auction_winner => -amount, company => amount}, reason, &1),
        &Messages.awaiting_set_stock_price(auction_winner, company, amount, &1)
      ]
    else
      _ -> nil
    end
  end

  handle_event "player_won_company_auction", ctx do
    %{auction_winner: auction_winner, company: company, bid_amount: amount} = ctx.payload
    [current_company: company, bidders: [{auction_winner, amount}]]
  end

  handle_event "awaiting_set_stock_price", _ctx do
    [awaiting_stock_price: true]
  end

  #########################################################
  # setting starting stock price
  # - must happen after a company opens
  #########################################################

  handle_command "set_stock_value", ctx do
    %{auction_winner: auction_winner, company: company, price: price} = ctx.payload
    projection = ctx.projection

    with :ok <- validate_auction_phase(projection),
         :ok <- validate_awaiting_stock_price_set(projection),
         :ok <- validate_bid_winner(projection, auction_winner),
         :ok <- validate_current_company(projection, company),
         :ok <- validate_stock_price_not_exceeds_bid(projection, price),
         :ok <- validate_stock_price_is_valid_spot_on_board(price) do
      &Messages.stock_value_set(auction_winner, company, price, &1)
    else
      {:error, reason} ->
        &Messages.stock_value_rejected(auction_winner, company, price, reason, &1)
    end
  end

  handle_event "stock_value_set", ctx do
    %{auction_winner: player_to_start_next_company_auction} = ctx.payload
    [start_bidder: player_to_start_next_company_auction] ++ @clear_company_auction
  end

  #########################################################
  # end the auction phase
  #########################################################

  defreaction maybe_end_auction_phase(%__MODULE__{} = projection) do
    with {:ok, phase_number} <- fetch_phase_number(projection),
         :ok <- validate_in_between_company_auctions(projection),
         {:error, _reason} <- fetch_next_company(projection) do
      start_player = projection.start_bidder
      &Messages.auction_phase_ended(phase_number, start_player, &1)
    else
      _ -> nil
    end
  end

  handle_event "auction_phase_ended", _ctx do
    @clear_auction
  end

  #########################################################
  # AUCTION PHASE
  #########################################################

  defp validate_auction_phase(projection) do
    if projection.phase_number do
      :ok
    else
      {:error, "no auction in progress"}
    end
  end

  defp fetch_phase_number(projection) do
    if phase_number = projection.phase_number do
      {:ok, phase_number}
    else
      {:error, "no phase number"}
    end
  end

  # but also prior to the first and after the last ... :P
  defp validate_in_between_company_auctions(projection) do
    if projection.current_company do
      {:error, "not in between company auctions"}
    else
      :ok
    end
  end

  #########################################################
  # CURRENT COMPANY
  #########################################################

  def fetch_next_company(projection) do
    case projection.remaining_companies do
      [next_company | _] -> {:ok, next_company}
      [] -> {:error, "no next company"}
    end
  end

  defp validate_company_auction(projection) do
    if projection.current_company do
      :ok
    else
      {:error, "no company auction in progress"}
    end
  end

  defp fetch_current_company(projection) do
    case projection.current_company do
      nil -> {:error, "no current company"}
      company -> {:ok, company}
    end
  end

  defp validate_current_company(projection, company) do
    with {:ok, current_company} <- fetch_current_company(projection) do
      case current_company do
        ^company -> :ok
        _ -> {:error, "incorrect company"}
      end
    end
  end

  #########################################################
  # BIDDERS
  #########################################################

  def fetch_start_bidder(projection) do
    if start_bidder = projection.start_bidder do
      {:ok, start_bidder}
    else
      {:error, "no start bidder"}
    end
  end

  defp fetch_bidders(projection) do
    with bidders when is_list(bidders) <- projection.bidders do
      {:ok, bidders}
    else
      _ -> {:error, "no bidders"}
    end
  end

  defp fetch_current_bidder(projection) do
    with {:ok, bidders} <- fetch_bidders(projection) do
      case bidders do
        [{bidder, _amount} | _] -> {:ok, bidder}
        [] -> {:error, "no current_bidder"}
      end
    end
  end

  defp fetch_single_bidder_and_amount(projection) do
    with {:ok, bidders} <- fetch_bidders(projection) do
      case bidders do
        [single_bidder] -> {:ok, single_bidder}
        _ -> {:error, "more than one bidder"}
      end
    end
  end

  defp fetch_single_bidder(projection) do
    with {:ok, {bidder, _amount}} <- fetch_single_bidder_and_amount(projection) do
      {:ok, bidder}
    end
  end

  defp validate_no_bidders(projection) do
    case projection.bidders do
      [] -> :ok
      _ -> {:error, "bidders still exist"}
    end
  end

  defp fetch_bid_winner(projection) do
    with {:ok, {bidder, amount}} <- fetch_single_bidder_and_amount(projection) do
      if is_integer(amount) do
        {:ok, bidder}
      else
        {:error, "There is one bidder left, but they haven't bid"}
      end
    end
  end

  defp validate_current_bidder(projection, bidder) do
    with {:ok, current_bidder} <- fetch_current_bidder(projection) do
      case current_bidder do
        ^bidder -> :ok
        _ -> {:error, "incorrect player"}
      end
    end
  end

  defp validate_bid_winner(projection, auction_winner) do
    with {:ok, bidder} <- fetch_bid_winner(projection) do
      case bidder do
        ^auction_winner -> :ok
        _ -> {:error, "incorrect player"}
      end
    end
  end

  #########################################################
  # BIDS
  #########################################################

  defp validate_min_bid(amount) do
    if amount >= 8 do
      :ok
    else
      {:error, "bid must be at least 8"}
    end
  end

  defp current_highest_bid(projection) do
    with {:ok, bidders} <- fetch_bidders(projection) do
      highest_bid =
        bidders
        |> Enum.map(&elem(&1, 1))
        |> Enum.filter(&is_integer/1)
        |> case do
          [] -> 0
          bids -> Enum.max(bids)
        end

      {:ok, highest_bid}
    end
  end

  defp validate_increasing_bid(projection, amount) do
    with {:ok, highest_bid} <- current_highest_bid(projection) do
      if highest_bid < amount do
        :ok
      else
        {:error, "bid must be higher than the current bid"}
      end
    end
  end

  defp validate_balance(projection, bidder, amount) do
    player_money_balance = projection.player_money_balances[bidder] || 0

    if player_money_balance < amount do
      {:error, "insufficient funds"}
    else
      :ok
    end
  end

  defp fetch_highest_bid(projection) do
    with {:ok, bidders} <- fetch_bidders(projection) do
      case Enum.reverse(bidders) do
        [last_and_therefore_highest_bidder | _] ->
          {_bidder, amount} = last_and_therefore_highest_bidder

          if is_integer(amount) do
            {:ok, amount}
          else
            {:error, "no bids"}
          end

        [] ->
          {:error, "no bidders"}
      end
    end
  end

  #########################################################
  # SETTING STOCK PRICE
  #########################################################

  # There is both a company up for auction,
  # no player has been determined the winner of it yet,
  # and so we're not yet awaiting the
  defp validate_bidding_in_progress(projection) do
    with :ok <- validate_company_auction(projection) do
      case validate_awaiting_stock_price_set(projection) do
        {:error, _} -> :ok
        :ok -> {:error, "incorrect subphase"}
      end
    end
  end

  defp validate_awaiting_stock_price_set(projection) do
    with {:ok, _} <- fetch_bid_winner(projection) do
      :ok
    else
      _ -> {:error, "not awaiting stock price"}
    end
  end

  defp validate_stock_price_is_valid_spot_on_board(price) do
    if price in TransSiberianRailroad.StockValue.stock_value_spaces() do
      :ok
    else
      {:error, "not one of the valid stock prices"}
    end
  end

  defp validate_stock_price_not_exceeds_bid(projection, price) do
    with {:ok, bid} <- fetch_highest_bid(projection) do
      if price <= bid do
        :ok
      else
        {:error, "price exceeds winning bid"}
      end
    end
  end
end
