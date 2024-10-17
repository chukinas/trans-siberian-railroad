defmodule TransSiberianRailroad.Aggregator.Auction do
  @moduledoc """
  This module handles all the events and commands related to the auctioning
  of rail companies to players.
  """

  use TypedStruct
  use TransSiberianRailroad.Aggregator
  require Logger
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
    field :player_order, [Player.id()]
    # TODO testing property: a player's and company's balance may never be negative.
    field :player_money_balances, %{Player.id() => integer()}, default: %{}
    field :state_machine, [term()], default: []
  end

  #########################################################
  # event handlers not specific to the auction
  #########################################################

  handle_event("player_order_set", ctx, do: [player_order: ctx.payload.player_order])

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

  #########################################################
  # start an auction phase and company auctions
  #########################################################

  handle_event "auction_phase_started", ctx do
    payload = ctx.payload
    %{phase_number: phase_number, starting_bidder: starting_bidder} = payload

    # TODO reimplement
    # TODO It's finally time to store each step of the projection.
    # Rebuilding it each time as I've been doing means that well-meaning warnings like this one
    # outpuut to the screen more that once (WAY more than once!!!)
    # if Enum.any?(ctx.projection.state_machine) do
    #   Logger.warning("""
    #   Auction phase already started
    #   Current projection:
    #   #{inspect(ctx.projection, pretty: true)}
    #   Event payload:
    #   #{inspect(payload, pretty: true)}
    #   """)
    # end

    auction_phase =
      {:auction_phase,
       phase_number: phase_number,
       starting_bidder: starting_bidder,
       remaining_companies:
         case phase_number do
           1 -> ~w(red blue green yellow)a
           2 -> ~w(black white)a
         end}

    [state_machine: [auction_phase]]
  end

  # TODO design a macro called... maybe_react
  defreaction maybe_start_company_auction(%__MODULE__{} = auction) do
    with [{:auction_phase, kv}] <- auction.state_machine,
         [next_company | _] <- Keyword.fetch!(kv, :remaining_companies) do
      starting_bidder = Keyword.fetch!(kv, :starting_bidder)
      metadata = Metadata.from_aggregator(auction)
      Messages.company_auction_started(starting_bidder, next_company, metadata)
    else
      _ -> nil
    end
  end

  # TODO if I return an invalid key, currently I get a very unhelpful error message,
  # one that doesn't mention the line the failed.
  # I expect to get a message that at least points me to the function or return value in this file.
  handle_event "company_auction_started", ctx do
    %{starting_bidder: starting_bidder, company: company} = ctx.payload

    remove_company_from_list = fn list ->
      Enum.reject(list, fn
        ^company -> true
        _ -> false
      end)
    end

    state_machine =
      ctx.projection.state_machine
      |> put_in([:auction_phase, :starting_bidder], starting_bidder)
      |> update_in([:auction_phase, :remaining_companies], remove_company_from_list)

    company_auction =
      with player_order = ctx.projection.player_order,
           player_ids = Players.player_order_once_around_the_table(player_order, starting_bidder),
           bidders = Enum.map(player_ids, &{&1, nil}) do
        {:company_auction, company: company, bidders: bidders}
      end

    [state_machine: [company_auction | state_machine]]
  end

  #########################################################
  # handle players passing on a company
  #########################################################

  handle_event "company_passed", ctx do
    %{player_id: player_id} = ctx.payload

    state_machine =
      ctx.projection.state_machine
      |> update_in([:company_auction, :bidders], fn [{^player_id, _} | rest] -> rest end)

    [state_machine: state_machine]
  end

  command_handler("pass_on_company", ctx) do
    auction = ctx.projection
    %{player_id: player_id, company_id: company_id} = ctx.payload
    metadata = Metadata.from_aggregator(auction)

    with :ok <- validate_current_bidder(auction, player_id),
         :ok <- validate_current_company(auction, company_id) do
      Messages.company_passed(player_id, company_id, metadata)
    else
      {:error, reason} ->
        Messages.company_pass_rejected(player_id, company_id, reason, metadata)
    end
  end

  # If all players pass on a company, the company auction ends, and the company is removed from the game
  defreaction maybe_not_open_company(auction) do
    with [{:company_auction, kv} | _] <- auction.state_machine,
         [] <- Keyword.fetch!(kv, :bidders) do
      company = Keyword.fetch!(kv, :company)
      metadata = Metadata.from_aggregator(auction)
      Messages.company_not_opened(company, metadata)
    else
      _ -> nil
    end
  end

  handle_event "company_not_opened", ctx do
    [_company_auction | state_machine] = ctx.projection.state_machine
    [state_machine: state_machine]
  end

  #########################################################
  # handle players bidding on a company
  #########################################################

  # TODO test property: all events have incrementing sequence numbers
  # TODO the command (and event) names should be validated.
  command_handler("submit_bid", ctx) do
    %{projection: auction, payload: payload} = ctx

    %{player_id: bidder, company_id: company_id, amount: amount} = payload

    validate_balance = fn ->
      player_money_balance = auction.player_money_balances[bidder] || 0

      if player_money_balance < amount do
        {:error, "insufficient funds"}
      else
        :ok
      end
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

    validate_min_bid =
      if amount < 8,
        do: {:error, "bid amount must be at least 8"},
        else: :ok

    validate_company = fn kv ->
      case Keyword.fetch!(kv, :company) do
        ^company_id -> :ok
        _incorrect_company -> {:error, "incorrect company"}
      end
    end

    metadata = Metadata.from_aggregator(auction)

    # TODO refactor to make use of kv
    with {:ok, kv} <- fetch_substate_kv(auction, :company_auction),
         :ok <- validate_current_bidder(auction, bidder),
         :ok <- validate_company.(kv),
         :ok <- validate_min_bid,
         :ok <- validate_increasing_bid.(kv),
         :ok <- validate_balance.() do
      Messages.company_bid(bidder, company_id, amount, metadata)
    else
      {:error, reason} -> Messages.bid_rejected(bidder, company_id, amount, reason, metadata)
    end
  end

  # TODO rename "bid_submitted"?
  handle_event "company_bid", ctx do
    %{player_id: bidder, amount: amount} = ctx.payload

    state_machine = ctx.projection.state_machine

    # TODO combine with above
    state_machine =
      update_in(state_machine, [:company_auction, :bidders], fn [{^bidder, _} | rest] ->
        rest ++ [{bidder, amount}]
      end)

    [state_machine: state_machine]
  end

  defreaction maybe_open_company(auction) do
    with [{:company_auction, kv} | _] <- auction.state_machine,
         # There's only one bidder left
         [{player_id, amount}] <- Keyword.fetch!(kv, :bidders),
         # That player's already made at least one bid
         true <- is_integer(amount) do
      company = Keyword.fetch!(kv, :company)
      metadata = Metadata.from_aggregator(auction)

      [
        Messages.company_opened(company, player_id, amount, metadata),
        Messages.money_transferred(
          %{player_id => -amount, company => amount},
          "Player #{player_id} won the auction for #{company}'s opening share",
          Metadata.from_aggregator(auction, 0)
        )
      ]
    else
      _ -> nil
    end
  end

  handle_event "company_opened", ctx do
    [_company_auction | state_machine] = ctx.projection.state_machine
    # TODO be consistent with player vs player_id
    %{player_id: player, company_id: company, bid_amount: amount} = ctx.payload

    setting_stock_price =
      {:setting_stock_price, player_id: player, company: company, max_price: amount}

    [state_machine: [setting_stock_price | state_machine]]
  end

  #########################################################
  # setting starting stock price
  # - must happen after a company opens
  #########################################################

  # TODO rm parens
  # TODO rename
  command_handler("set_starting_stock_price", ctx) do
    auction = ctx.projection
    %{player_id: player_id, company_id: company_id, price: price} = ctx.payload
    metadata = Metadata.from_aggregator(auction)

    validate_current_company = fn kv ->
      case Keyword.fetch!(kv, :company) do
        ^company_id -> :ok
        _incorrect_company -> {:error, "incorrect company"}
      end
    end

    validate_bid_winner = fn kv ->
      case Keyword.fetch!(kv, :player_id) do
        ^player_id -> :ok
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
         :ok <- validate_current_company.(kv),
         :ok <- validate_bid_winner.(kv),
         :ok <- validate_stock_price.(kv) do
      Messages.starting_stock_price_set(player_id, company_id, price, metadata)
    else
      {:error, reason} ->
        Messages.starting_stock_price_rejected(player_id, company_id, price, reason, metadata)
    end
  end

  handle_event "starting_stock_price_set", ctx do
    # TODO be consistent with extracting payload first
    %{player_id: player_to_start_next_company_auction} = ctx.payload

    auction_phase_kv =
      ctx.projection.state_machine
      |> Keyword.fetch!(:auction_phase)
      |> Keyword.replace!(:starting_bidder, player_to_start_next_company_auction)

    [state_machine: [{:auction_phase, auction_phase_kv}]]
  end

  #########################################################
  # end the auction phase
  #########################################################

  defreaction maybe_end_auction_phase(%__MODULE__{} = auction) do
    with [{:auction_phase, kv}] <- auction.state_machine,
         [] <- Keyword.fetch!(kv, :remaining_companies) do
      phase_number = Keyword.fetch!(kv, :phase_number)
      metadata = Metadata.from_aggregator(auction)
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

  defp fetch_substate(auction) do
    case auction.state_machine do
      [] -> {:error, "no auction in progress"}
      [_auction_phase] -> {:error, "no substate"}
      [substate, _auction_phase] -> {:ok, substate}
    end
  end

  defp fetch_substate_kv(auction, substate_name)
       when substate_name in ~w(company_auction setting_stock_price)a do
    with {:ok, substate} <- fetch_substate(auction),
         {^substate_name, kv} <- substate do
      {:ok, kv}
    else
      {:error, reason} ->
        {:error, reason}

      {_substate_name, _kv} ->
        {:error, "not in the correct phase of the auction"}
    end
  end

  defp fetch_current_bidder(auction) do
    with {:ok, kv} <- fetch_substate_kv(auction, :company_auction),
         [current_bidder_tuple | _] <- Keyword.fetch!(kv, :bidders) do
      {player_id, _bid} = current_bidder_tuple
      {:ok, player_id}
    else
      {:error, reason} -> {:error, reason}
      [] -> {:error, "no current bidder"}
    end
  end

  defp validate_current_bidder(auction, player_id) do
    case fetch_current_bidder(auction) do
      {:ok, ^player_id} ->
        :ok

      {:ok, _current_player} ->
        {:error, "incorrect player"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp validate_current_company(auction, company_id) do
    with {:ok, kv} <- fetch_substate_kv(auction, :company_auction),
         ^company_id <- Keyword.fetch!(kv, :company) do
      :ok
    else
      {:error, reason} -> {:error, reason}
      current_company -> {:error, "#{inspect(current_company)} is the current company"}
    end
  end

  #########################################################
  # GLUE
  #########################################################

  # TODO rm
  def events_from_projection(auction) do
    Enum.find_value(reaction_fns(), & &1.(auction))
  end

  # TODO rm
  @spec handle_command(t(), String.t(), map()) :: Event.t()
  defp handle_command(projection, command_name, payload) do
    grapefruit(command_name, %{projection: projection, payload: payload})
  end
end
