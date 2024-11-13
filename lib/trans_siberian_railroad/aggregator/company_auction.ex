defmodule TransSiberianRailroad.Aggregator.CompanyAuction do
  @moduledoc """
  This module handles all the events and commands related to the auctioning
  of a company's first stock certificate to players.

  This aggregator listens for `company_auction_started` and emits `company_auction_ended` when it's done.

  Players take turns bidding or passing on the company.
  To bid, you have to bid at least 8 and more than any amount anyone else has bid on that company so far.
  Eventually, one of two things happens:
  - all players pass on the company. The company is removed from the game.
  - only one player is left. That player wins the company and pays the amount they bid for it. They get the company's stock certificate.
    The company is now "open".
  """

  use TransSiberianRailroad.Aggregator
  use TransSiberianRailroad.Projection
  require TransSiberianRailroad.Constants, as: Constants
  alias TransSiberianRailroad.Aggregator.StockValue
  alias TransSiberianRailroad.Messages
  alias TransSiberianRailroad.Players
  alias TransSiberianRailroad.RailLinks

  aggregator_typedstruct do
    # These are tracked continuously throughout the game
    field :player_order, [Constants.player()]
    field :player_money, %{Constants.player() => non_neg_integer()}, default: %{}
    field :built_rail_links, [RailLinks.rail_link()], default: []

    # Set only at the start of the company auction
    field :company, Constants.company()

    # These two track the state of the company auction
    field :bidders, [{Constants.player(), nil | non_neg_integer()}], default: []
    field :next, [term()], default: []
    field :awaiting, term()
  end

  #########################################################
  # event handlers not specific to the auction
  #########################################################

  handle_event "player_order_set", ctx do
    [player_order: ctx.payload.player_order]
  end

  handle_event "money_transferred", ctx do
    transfers = ctx.payload.transfers
    player_money = ctx.projection.player_money

    new_player_money_balances =
      Enum.reduce(transfers, player_money, fn
        {entity, amount}, balances when Constants.is_player(entity) ->
          Map.update(balances, entity, amount, &(&1 + amount))

        _, balances ->
          balances
      end)

    [player_money: new_player_money_balances]
  end

  #########################################################
  # start an auction phase and company auctions
  #########################################################

  handle_event "company_auction_started", ctx do
    %{start_bidder: start_bidder, company: company} = ctx.payload

    [
      company: company,
      bidders:
        ctx.projection.player_order
        |> Players.one_round(start_bidder)
        |> Enum.map(&{&1, nil})
    ]
  end

  #########################################################
  # Awaiting bid or pass
  #########################################################

  defreaction maybe_awaiting_bid_or_pass(projection) do
    with nil <- projection.awaiting,
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

  handle_event "awaiting_bid_or_pass", _ctx do
    [awaiting: "bid_or_pass"]
  end

  #########################################################
  # handle players passing on a company
  #########################################################

  handle_command "pass_on_company", ctx do
    %{passing_player: passing_player, company: company} = ctx.payload
    projection = ctx.projection

    with :ok <- validate_company_auction(projection),
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
    [bidders: bidders, awaiting: nil]
  end

  defreaction maybe_all_players_passed_on_company(projection) do
    with :ok <- validate_no_bidders(projection),
         {:ok, company} <- fetch_current_company(projection) do
      &Messages.all_players_passed_on_company(company, &1)
    else
      _ -> nil
    end
  end

  #########################################################
  # handle players bidding on a company
  #########################################################

  handle_command "submit_bid", ctx do
    %{bidder: bidder, company: company, amount: amount} = ctx.payload
    projection = ctx.projection

    with :ok <- validate_company_auction(projection),
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
      bidders:
        with [{^bidder, _} | rest] = ctx.projection.bidders do
          rest ++ [{bidder, amount}]
        end,
      awaiting: nil
    ]
  end

  defreaction maybe_player_won_company_auction(projection) do
    with nil <- projection.awaiting,
         :ok <- validate_company_auction(projection),
         {:ok, company} <- fetch_current_company(projection),
         {:ok, auction_winner} <- fetch_single_bidder(projection),
         {:ok, amount} <- fetch_highest_bid(projection) do
      reason = "company stock auctioned off"

      available_links = RailLinks.connected_to("moscow") -- projection.built_rail_links

      [
        &Messages.player_won_company_auction(auction_winner, company, amount, &1),
        &Messages.stock_certificates_transferred(company, company, auction_winner, 1, reason, &1),
        &Messages.money_transferred(%{auction_winner => -amount, company => amount}, reason, &1),
        &Messages.awaiting_rail_link(auction_winner, company, available_links, &1),
        &Messages.awaiting_stock_value(auction_winner, company, amount, &1)
      ]
    else
      _ -> nil
    end
  end

  handle_event "player_won_company_auction", ctx do
    %{auction_winner: auction_winner, bid_amount: amount} = ctx.payload
    [bidders: [{auction_winner, amount}]]
  end

  #########################################################
  # initial rail link
  #########################################################

  handle_command "build_rail_link", ctx do
    %{player: building_player, company: company, rail_link: rail_link} = ctx.payload
    projection = ctx.projection

    with :ok <- validate_company_auction(projection),
         :ok <- validate_current_bidder(projection, building_player),
         :ok <- validate_current_company(projection, company),
         :ok <- RailLinks.validate_rail_link(rail_link),
         :ok <- validate_unbuilt_rail_link(projection, rail_link),
         :ok <- validate_connected_link(rail_link) do
      &Messages.rail_link_built(building_player, company, rail_link, &1)
    else
      {:error, reason} ->
        &Messages.rail_link_rejected(building_player, company, rail_link, reason, &1)
    end
  end

  #########################################################
  # setting starting stock price
  # - must happen after a company opens
  #########################################################

  handle_command "set_stock_value", ctx do
    %{auction_winner: auction_winner, company: company, price: price} = ctx.payload
    projection = ctx.projection

    with :ok <- validate_company_auction(projection),
         :ok <- validate_awaiting_stock_value(projection),
         :ok <- validate_bid_winner(projection, auction_winner),
         :ok <- validate_current_company(projection, company),
         :ok <- validate_stock_value_not_exceeds_bid(projection, price),
         :ok <- validate_stock_value_is_valid_spot_on_board(price) do
      &Messages.stock_value_set(auction_winner, company, price, &1)
    else
      {:error, reason} ->
        &Messages.stock_value_rejected(auction_winner, company, price, reason, &1)
    end
  end

  #########################################################
  # End company auction
  #########################################################

  defp add_awaiting(ctx, event_name) do
    awaiting =
      [event_name, "company_auction_ended", List.wrap(ctx.projection.awaiting)]
      |> List.flatten()
      |> Enum.uniq()

    [awaiting: awaiting]
  end

  def drop_awaiting(ctx, event_name) do
    awaiting =
      if awaiting = ctx.projection.awaiting do
        Enum.reject(awaiting, &(&1 == event_name))
      end

    [awaiting: awaiting]
  end

  handle_event "awaiting_rail_link", ctx do
    add_awaiting(ctx, "rail_link_built")
  end

  handle_event "rail_link_built", ctx do
    %{rail_link: rail_link} = ctx.payload
    built_rail_links = ctx.projection.built_rail_links

    drop_awaiting(ctx, "rail_link_built")
    |> Keyword.put(:built_rail_links, [rail_link | built_rail_links])
  end

  handle_event "awaiting_stock_value", ctx do
    add_awaiting(ctx, "stock_value_set")
  end

  handle_event "stock_value_set", ctx do
    drop_awaiting(ctx, "stock_value_set")
  end

  handle_event "all_players_passed_on_company", ctx do
    add_awaiting(ctx, "company_auction_ended")
  end

  defreaction maybe_end_company_auction(projection, _reaction_ctx) do
    if ["company_auction_ended"] == projection.awaiting do
      &Messages.company_auction_ended(projection.company, &1)
    end
  end

  handle_event "company_auction_ended", _ctx do
    [
      company: nil,
      bidders: [],
      awaiting: nil
    ]
  end

  #########################################################
  # CONVERTERS
  #########################################################

  # Current Company
  #########################################################

  defp validate_company_auction(projection) do
    if projection.company do
      :ok
    else
      {:error, "no company auction in progress"}
    end
  end

  defp fetch_current_company(projection) do
    case projection.company do
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

  # Bidders
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

  # Bids
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
    player_money_balance = projection.player_money[bidder] || 0

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

  # Rail Links
  #########################################################

  defp validate_unbuilt_rail_link(projection, rail_link) do
    if rail_link in projection.built_rail_links do
      {:error, "link already built"}
    else
      :ok
    end
  end

  defp validate_connected_link(rail_link) do
    # temp implementation
    if "moscow" in rail_link do
      :ok
    else
      {:error, "unconnected rail link"}
    end
  end

  # Setting stock price
  #########################################################

  # There is both a company up for auction,
  # no player has been determined the winner of it yet,
  # and so we're not yet awaiting the
  defp validate_bidding_in_progress(projection) do
    with :ok <- validate_company_auction(projection) do
      case validate_awaiting_stock_value(projection) do
        {:error, _} -> :ok
        :ok -> {:error, "bidding is closed"}
      end
    end
  end

  defp validate_awaiting_stock_value(projection) do
    with {:ok, _} <- fetch_bid_winner(projection) do
      :ok
    else
      _ -> {:error, "not awaiting stock price"}
    end
  end

  defp validate_stock_value_is_valid_spot_on_board(price) do
    if price in StockValue.stock_value_spaces() do
      :ok
    else
      {:error, "not one of the valid stock prices"}
    end
  end

  defp validate_stock_value_not_exceeds_bid(projection, price) do
    with {:ok, bid} <- fetch_highest_bid(projection) do
      if price <= bid do
        :ok
      else
        {:error, "price exceeds winning bid"}
      end
    end
  end
end
