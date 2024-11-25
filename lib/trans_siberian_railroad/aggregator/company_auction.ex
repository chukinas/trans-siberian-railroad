defmodule Tsr.Aggregator.CompanyAuction do
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

  use Tsr.Aggregator
  alias Tsr.Aggregator.BoardState.StockValue
  alias Tsr.Players
  alias Tsr.RailLinks

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

  handle_event "rubles_transferred", ctx do
    transfers = ctx.payload.transfers
    player_money = ctx.projection.player_money

    new_player_money_balances =
      Enum.reduce(transfers, player_money, fn %{entity: entity, rubles: rubles}, balances ->
        if Constants.is_player(entity) do
          Map.update(balances, entity, rubles, &(&1 + rubles))
        else
          balances
        end
      end)

    [player_money: new_player_money_balances]
  end

  #########################################################
  # start an auction phase and company auctions
  #########################################################

  handle_event "company_auction_started", ctx do
    %{start_player: start_player, company: company} = ctx.payload

    [
      company: company,
      bidders:
        ctx.projection.player_order
        |> Players.one_round(start_player)
        |> Enum.map(&{&1, nil})
    ]
  end

  #########################################################
  # Awaiting bid or pass
  #########################################################

  defreaction maybe_awaiting_bid_or_pass(%{projection: projection}) do
    with nil <- projection.awaiting,
         :ok <- validate_bidding_in_progress(projection),
         {:ok, company} <- fetch_current_company(projection),
         {:ok, player} <- fetch_current_bidder(projection) do
      min_bid =
        case fetch_highest_bid(projection) do
          {:ok, rubles} -> rubles + 1
          {:error, _} -> 8
        end

      event_builder("awaiting_bid_or_pass", player: player, company: company, min_bid: min_bid)
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
    %{player: passing_player, company: company} = ctx.payload
    projection = ctx.projection

    with :ok <- validate_company_auction(projection),
         :ok <- validate_bidding_in_progress(projection),
         :ok <- validate_current_bidder(projection, passing_player),
         :ok <- validate_current_company(projection, company) do
      event_builder("company_passed", player: passing_player, company: company)
    else
      {:error, reason} ->
        event_builder("company_pass_rejected",
          player: passing_player,
          company: company,
          reason: reason
        )
    end
  end

  handle_event "company_passed", ctx do
    %{player: passing_player} = ctx.payload
    bidders = Enum.reject(ctx.projection.bidders, fn {player, _} -> player == passing_player end)
    [bidders: bidders, awaiting: nil]
  end

  defreaction maybe_all_players_passed_on_company(%{projection: projection}) do
    with :ok <- validate_no_bidders(projection),
         {:ok, company} <- fetch_current_company(projection) do
      event_builder("all_players_passed_on_company", company: company)
    else
      _ -> nil
    end
  end

  #########################################################
  # handle players bidding on a company
  #########################################################

  handle_command "submit_bid", ctx do
    %{player: bidder, company: company, rubles: rubles} = ctx.payload
    projection = ctx.projection

    with :ok <- validate_company_auction(projection),
         :ok <- validate_bidding_in_progress(projection),
         :ok <- validate_current_bidder(projection, bidder),
         :ok <- validate_current_company(projection, company),
         :ok <- validate_min_bid(rubles),
         :ok <- validate_increasing_bid(projection, rubles),
         :ok <- validate_balance(projection, bidder, rubles) do
      event_builder("bid_submitted", player: bidder, company: company, rubles: rubles)
    else
      {:error, reason} ->
        event_builder("bid_rejected",
          player: bidder,
          company: company,
          rubles: rubles,
          reason: reason
        )
    end
  end

  handle_event "bid_submitted", ctx do
    %{player: bidder, rubles: rubles} = ctx.payload

    [
      bidders:
        with [{^bidder, _} | rest] = ctx.projection.bidders do
          rest ++ [{bidder, rubles}]
        end,
      awaiting: nil
    ]
  end

  defreaction maybe_player_won_company_auction(%{projection: projection}) do
    with nil <- projection.awaiting,
         :ok <- validate_company_auction(projection),
         {:ok, company} <- fetch_current_company(projection),
         {:ok, auction_winner} <- fetch_single_bidder(projection),
         {:ok, rubles} <- fetch_highest_bid(projection) do
      reason = "company stock auctioned off"

      available_links = RailLinks.get_connecting("moscow") -- projection.built_rail_links

      [
        event_builder("player_won_company_auction",
          player: auction_winner,
          company: company,
          rubles: rubles
        ),
        event_builder("stock_certificates_transferred",
          company: company,
          from: company,
          to: auction_winner,
          count: 1,
          reason: reason
        ),
        event_builder("awaiting_initial_rail_link",
          player: auction_winner,
          company: company,
          available_links: available_links
        ),
        event_builder("awaiting_stock_value",
          player: auction_winner,
          company: company,
          max_stock_value: rubles
        )
      ]
    else
      _ -> nil
    end
  end

  handle_event "player_won_company_auction", ctx do
    %{player: auction_winner, rubles: rubles} = ctx.payload
    [bidders: [{auction_winner, rubles}]]
  end

  #########################################################
  # initial rail link
  #########################################################

  handle_command "build_initial_rail_link", ctx do
    %{player: building_player, company: company, rail_link: rail_link} = ctx.payload
    projection = ctx.projection

    with :ok <- validate_company_auction(projection),
         :ok <- validate_current_bidder(projection, building_player),
         :ok <- validate_current_company(projection, company),
         {:ok, link_income} <- RailLinks.fetch_income(rail_link),
         :ok <- validate_unbuilt_rail_link(projection, rail_link),
         :ok <- validate_connected_link(rail_link) do
      event_builder("initial_rail_link_built",
        player: building_player,
        company: company,
        rail_link: rail_link,
        link_income: link_income
      )
    else
      {:error, reason} ->
        event_builder("initial_rail_link_rejected",
          player: building_player,
          company: company,
          rail_link: rail_link,
          reason: reason
        )
    end
  end

  #########################################################
  # setting starting stock value
  # - must happen after a company opens
  #########################################################

  handle_command "set_stock_value", ctx do
    %{player: auction_winner, company: company, stock_value: stock_value} = ctx.payload
    projection = ctx.projection

    with :ok <- validate_company_auction(projection),
         :ok <- validate_awaiting_stock_value(projection),
         :ok <- validate_bid_winner(projection, auction_winner),
         :ok <- validate_current_company(projection, company),
         :ok <- validate_stock_value_not_exceeds_bid(projection, stock_value),
         :ok <- validate_stock_value_is_valid_spot_on_board(stock_value) do
      event_builder("stock_value_set",
        player: auction_winner,
        company: company,
        stock_value: stock_value
      )
    else
      {:error, reason} ->
        event_builder("stock_value_rejected",
          player: auction_winner,
          company: company,
          stock_value: stock_value,
          reason: reason
        )
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

  handle_event "awaiting_initial_rail_link", ctx do
    add_awaiting(ctx, "initial_rail_link_built")
  end

  handle_event "initial_rail_link_built", ctx do
    %{rail_link: rail_link} = ctx.payload
    built_rail_links = ctx.projection.built_rail_links

    drop_awaiting(ctx, "initial_rail_link_built")
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

  defreaction maybe_end_company_auction(%{projection: projection}) do
    if ["company_auction_ended"] == projection.awaiting do
      event_builder("company_auction_ended", company: projection.company)
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

  def fetch_start_player(projection) do
    if start_player = projection.start_player do
      {:ok, start_player}
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
    with {:ok, {bidder, rubles}} <- fetch_single_bidder_and_amount(projection) do
      if is_integer(rubles) do
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

  defp validate_min_bid(rubles) do
    if rubles >= 8 do
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

  defp validate_increasing_bid(projection, rubles) do
    with {:ok, highest_bid} <- current_highest_bid(projection) do
      if highest_bid < rubles do
        :ok
      else
        {:error, "bid must be higher than the current bid"}
      end
    end
  end

  defp validate_balance(projection, bidder, rubles) do
    player_money_balance = projection.player_money[bidder] || 0

    if player_money_balance < rubles do
      {:error, "insufficient funds"}
    else
      :ok
    end
  end

  defp fetch_highest_bid(projection) do
    with {:ok, bidders} <- fetch_bidders(projection) do
      case Enum.reverse(bidders) do
        [last_and_therefore_highest_bidder | _] ->
          {_bidder, rubles} = last_and_therefore_highest_bidder

          if is_integer(rubles) do
            {:ok, rubles}
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

  # Setting stock value
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
      _ -> {:error, "not awaiting stock value"}
    end
  end

  defp validate_stock_value_is_valid_spot_on_board(value) do
    if value in StockValue.stock_value_spaces() do
      :ok
    else
      {:error, "not one of the valid stock values"}
    end
  end

  defp validate_stock_value_not_exceeds_bid(projection, value) do
    with {:ok, bid} <- fetch_highest_bid(projection) do
      if value <= bid do
        :ok
      else
        {:error, "stock value exceeds winning bid"}
      end
    end
  end
end
