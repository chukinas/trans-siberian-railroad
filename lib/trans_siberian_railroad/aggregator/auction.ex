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
  use TypedStruct
  require Logger
  alias TransSiberianRailroad.Aggregator.Players
  alias TransSiberianRailroad.Messages
  alias TransSiberianRailroad.Player

  #########################################################
  # PROJECTION
  #########################################################

  typedstruct opaque: true do
    version_field()
    field :player_order, [Player.id()]
    field :player_money_balances, %{Player.id() => integer()}, default: %{}
    field :state_machine, [{:atom, Keyword.t()}], default: []
  end

  #########################################################
  # event handlers not specific to the auction
  #########################################################

  handle_event("player_order_set", ctx, do: [player_order: ctx.payload.player_order])

  # We keep track of players' money because they need to pay for companies they win in auctions.
  handle_event "money_transferred", ctx do
    transfers = ctx.payload.transfers
    player_money_balances = ctx.projection.player_money_balances

    new_player_money_balances =
      Enum.reduce(transfers, player_money_balances, fn
        {entity, amount}, balances when is_integer(entity) ->
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

    auction_phase =
      {:auction_phase,
       phase_number: phase_number,
       start_bidder: start_bidder,
       remaining_companies:
         case phase_number do
           1 -> ~w(red blue green yellow)a
           2 -> ~w(black white)a
         end}

    [state_machine: [auction_phase]]
  end

  defreaction maybe_start_company_auction(%__MODULE__{} = auction) do
    with [{:auction_phase, kv}] <- auction.state_machine,
         [next_company | _] <- Keyword.fetch!(kv, :remaining_companies) do
      start_bidder = Keyword.fetch!(kv, :start_bidder)
      metadata = Projection.next_metadata(auction)
      Messages.company_auction_started(start_bidder, next_company, metadata)
    else
      _ -> nil
    end
  end

  handle_event "company_auction_started", ctx do
    %{start_bidder: start_bidder, company: company} = ctx.payload

    remove_company_from_list = fn list ->
      Enum.reject(list, fn
        ^company -> true
        _ -> false
      end)
    end

    state_machine =
      ctx.projection.state_machine
      |> put_in([:auction_phase, :start_bidder], start_bidder)
      |> update_in([:auction_phase, :remaining_companies], remove_company_from_list)

    company_auction =
      with player_order = ctx.projection.player_order,
           player_ids = Players.player_order_once_around_the_table(player_order, start_bidder),
           bidders = Enum.map(player_ids, &{&1, nil}) do
        {:company_auction, company: company, bidders: bidders}
      end

    [state_machine: [company_auction | state_machine]]
  end

  #########################################################
  # handle players passing on a company
  #########################################################

  handle_command "pass_on_company", ctx do
    %{passing_player: passing_player, company: company} = ctx.payload
    auction = ctx.projection
    metadata = Projection.next_metadata(auction)

    validate_current_company = fn auction, company ->
      with {:ok, kv} <- fetch_substate_kv(auction, :company_auction),
           ^company <- Keyword.fetch!(kv, :company) do
        :ok
      else
        {:error, reason} -> {:error, reason}
        _current_company -> {:error, "incorrect company"}
      end
    end

    with :ok <- validate_current_bidder(auction, passing_player),
         :ok <- validate_current_company.(auction, company) do
      Messages.company_passed(passing_player, company, metadata)
    else
      {:error, reason} ->
        Messages.company_pass_rejected(passing_player, company, reason, metadata)
    end
  end

  handle_event "company_passed", ctx do
    %{passing_player: passing_player} = ctx.payload

    state_machine =
      ctx.projection.state_machine
      |> update_in([:company_auction, :bidders], fn [{^passing_player, _} | rest] -> rest end)

    [state_machine: state_machine]
  end

  defreaction maybe_all_players_passed_on_company(auction) do
    with [{:company_auction, kv} | _] <- auction.state_machine,
         [] <- Keyword.fetch!(kv, :bidders) do
      company = Keyword.fetch!(kv, :company)
      metadata = Projection.next_metadata(auction)
      Messages.all_players_passed_on_company(company, metadata)
    else
      _ -> nil
    end
  end

  handle_event "all_players_passed_on_company", ctx do
    [_company_auction | state_machine] = ctx.projection.state_machine
    [state_machine: state_machine]
  end

  #########################################################
  # handle players bidding on a company
  #########################################################

  handle_command "submit_bid", ctx do
    %{bidder: bidder, company: company, amount: amount} = ctx.payload
    auction = ctx.projection

    validate_balance = fn ->
      player_money_balance = auction.player_money_balances[bidder] || 0

      if player_money_balance < amount do
        {:error, "insufficient funds"}
      else
        :ok
      end
    end

    validate_company = fn kv ->
      if Keyword.fetch!(kv, :company) == company, do: :ok, else: {:error, "incorrect company"}
    end

    validate_increasing_bid = fn kv ->
      current_bid =
        Keyword.fetch!(kv, :bidders)
        |> Enum.reduce(0, fn {_player, bid}, max_bid ->
          if is_integer(bid) do
            max(bid, max_bid)
          else
            max_bid
          end
        end)

      if current_bid < amount, do: :ok, else: {:error, "bid must be higher than the current bid"}
    end

    validate_min_bid = if amount < 8, do: {:error, "bid must be at least 8"}, else: :ok

    metadata = Projection.next_metadata(auction)

    with {:ok, kv} <- fetch_substate_kv(auction, :company_auction),
         :ok <- validate_current_bidder(auction, bidder),
         :ok <- validate_company.(kv),
         :ok <- validate_min_bid,
         :ok <- validate_increasing_bid.(kv),
         :ok <- validate_balance.() do
      Messages.bid_submitted(bidder, company, amount, metadata)
    else
      {:error, reason} -> Messages.bid_rejected(bidder, company, amount, reason, metadata)
    end
  end

  handle_event "bid_submitted", ctx do
    %{bidder: bidder, amount: amount} = ctx.payload

    state_machine =
      ctx.projection.state_machine
      |> update_in([:company_auction, :bidders], fn [{^bidder, _} | rest] ->
        rest ++ [{bidder, amount}]
      end)

    [state_machine: state_machine]
  end

  defreaction maybe_player_won_company_auction(auction) do
    with [{:company_auction, kv} | _] <- auction.state_machine,
         # There's only one bidder left
         [{auction_winner, amount}] <- Keyword.fetch!(kv, :bidders),
         # That player's already made at least one bid
         true <- is_integer(amount) do
      company = Keyword.fetch!(kv, :company)
      metadata = &Projection.next_metadata(auction, &1)

      [
        Messages.player_won_company_auction(auction_winner, company, amount, metadata.(0)),
        Messages.money_transferred(
          %{auction_winner => -amount, company => amount},
          "Player #{auction_winner} won the auction for #{company}'s opening share",
          metadata.(1)
        )
      ]
    else
      _ -> nil
    end
  end

  handle_event "player_won_company_auction", ctx do
    %{auction_winner: auction_winner, company: company, bid_amount: amount} = ctx.payload
    [_company_auction | state_machine] = ctx.projection.state_machine

    setting_stock_price =
      {:setting_stock_price, auction_winner: auction_winner, company: company, max_price: amount}

    [state_machine: [setting_stock_price | state_machine]]
  end

  #########################################################
  # setting starting stock price
  # - must happen after a company opens
  #########################################################

  handle_command "set_starting_stock_price", ctx do
    %{auction_winner: auction_winner, company: company, price: price} = ctx.payload
    auction = ctx.projection
    metadata = Projection.next_metadata(auction)

    validate_company = fn kv ->
      if Keyword.fetch!(kv, :company) == company, do: :ok, else: {:error, "incorrect company"}
    end

    validate_bid_winner = fn kv ->
      case Keyword.fetch!(kv, :auction_winner) do
        ^auction_winner -> :ok
        _ -> {:error, "incorrect player"}
      end
    end

    validate_stock_price = fn kv ->
      cond do
        Keyword.fetch!(kv, :max_price) < price ->
          {:error, "price exceeds winning bid"}

        price not in TransSiberianRailroad.StockValue.stock_value_spaces() ->
          {:error, "not one of the valid stock prices"}

        true ->
          :ok
      end
    end

    with {:ok, kv} <- fetch_substate_kv(auction, :setting_stock_price),
         :ok <- validate_bid_winner.(kv),
         :ok <- validate_company.(kv),
         :ok <- validate_stock_price.(kv) do
      Messages.starting_stock_price_set(auction_winner, company, price, metadata)
    else
      {:error, reason} ->
        Messages.starting_stock_price_rejected(auction_winner, company, price, reason, metadata)
    end
  end

  handle_event "starting_stock_price_set", ctx do
    %{auction_winner: player_to_start_next_company_auction} = ctx.payload

    auction_phase_kv =
      ctx.projection.state_machine
      |> Keyword.fetch!(:auction_phase)
      |> Keyword.replace!(:start_bidder, player_to_start_next_company_auction)

    [state_machine: [{:auction_phase, auction_phase_kv}]]
  end

  #########################################################
  # end the auction phase
  #########################################################

  defreaction maybe_end_auction_phase(%__MODULE__{} = auction) do
    with [{:auction_phase, kv}] <- auction.state_machine,
         [] <- Keyword.fetch!(kv, :remaining_companies) do
      phase_number = Keyword.fetch!(kv, :phase_number)
      metadata = Projection.next_metadata(auction)
      Messages.auction_phase_ended(phase_number, metadata)
    else
      _ -> nil
    end
  end

  handle_event "auction_phase_ended", _ctx do
    [state_machine: []]
  end

  #########################################################
  # CONVERTERS
  #########################################################

  defp fetch_substate_kv(auction, substate_name)
       when substate_name in ~w(company_auction setting_stock_price)a do
    fetch_substate = fn auction ->
      case auction.state_machine do
        [] -> {:error, "no auction in progress"}
        [_auction_phase] -> {:error, "no substate"}
        [substate, _auction_phase] -> {:ok, substate}
      end
    end

    with {:ok, substate} <- fetch_substate.(auction),
         {^substate_name, kv} <- substate do
      {:ok, kv}
    else
      {:error, reason} -> {:error, reason}
      {_substate_name, _kv} -> {:error, "incorrect subphase"}
    end
  end

  defp validate_current_bidder(auction, bidder) do
    current_bidder =
      with {:ok, kv} <- fetch_substate_kv(auction, :company_auction),
           [current_bidder_tuple | _] <- Keyword.fetch!(kv, :bidders) do
        {bidder, _bid} = current_bidder_tuple
        {:ok, bidder}
      else
        {:error, reason} -> {:error, reason}
        [] -> {:error, "no current bidder"}
      end

    case current_bidder do
      {:ok, ^bidder} ->
        :ok

      {:ok, _current_player} ->
        {:error, "incorrect player"}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
