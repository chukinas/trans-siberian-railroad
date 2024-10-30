defmodule TransSiberianRailroad.Messages do
  @moduledoc """
  This module contains **all** the constructors for `TransSiberianRailroad.Command`
  and `TransSiberianRailroad.Event`.

  The messages described in this file **completely** describe the game's player actions and events (found in rulebook.pdf).
  """

  use TransSiberianRailroad.Command
  require TransSiberianRailroad.Metadata, as: Metadata
  require TransSiberianRailroad.Player, as: Player
  require TransSiberianRailroad.Company, as: Company
  alias TransSiberianRailroad.Event

  #########################################################
  # - Local boilerplate reduction
  # - Accumulate command and event names
  #   in order to validate then in aggregators
  #########################################################

  Module.register_attribute(__MODULE__, :event_names, accumulate: true)
  Module.register_attribute(__MODULE__, :simple_event, accumulate: true)

  defmacrop event(fields) do
    name =
      with {name, _arity} = __CALLER__.function do
        to_string(name)
      end

    Module.put_attribute(__MODULE__, :event_names, name)

    quote do
      name = unquote(name)
      payload = Map.new(unquote(fields))
      metadata = var!(metadata)
      TransSiberianRailroad.Event.new(name, payload, metadata)
    end
  end

  #########################################################
  # "Broad Events"
  # Unlike all the other events, these two events may
  # be issued by **any** aggregator.
  #########################################################

  @type entity() :: Player.id() | Company.id() | :bank

  # Money
  # Moving money between players, bank, and companies is
  # such a common operation that it's all handled via this
  # single event.
  # This is one of the few (only?) messages that can be
  # issued by any Aggregator.
  @type amount() :: integer()
  @spec money_transferred(%{entity() => amount()}, String.t(), Metadata.t()) :: Event.t()
  def money_transferred(%{} = transfers, reason, metadata) when is_binary(reason) do
    0 = transfers |> Map.values() |> Enum.sum()
    event(transfers: transfers, reason: reason)
  end

  @spec stock_certificates_transferred(
          Company.id(),
          entity(),
          entity(),
          pos_integer(),
          String.t(),
          Metadata.t()
        ) ::
          Event.t()
  def stock_certificates_transferred(company, from, to, quantity, reason, metadata)
      when quantity in 1..5 do
    event(company: company, from: from, to: to, quantity: quantity, reason: reason)
  end

  #########################################################
  # Initializing Game
  #########################################################

  # OK
  defcommand initialize_game() do
    game_id =
      1..6
      |> Enum.map(fn _ -> Enum.random(?A..?Z) end)
      |> Enum.join()

    [game_id: game_id]
  end

  def game_initialized(game_id, metadata) do
    event(game_id: game_id)
  end

  def game_initialization_rejected(game_id, reason, metadata) do
    event(game_id: game_id, reason: reason)
  end

  #########################################################
  # Adding Players
  #########################################################

  # OK
  defcommand add_player(player_name) when is_binary(player_name) do
    [player_name: player_name]
  end

  def player_added(player_id, player_name, metadata)
      when Player.is_id(player_id) and is_binary(player_name) do
    event(player_id: player_id, player_name: player_name)
  end

  def player_rejected(player_name, reason, metadata) when is_binary(reason) do
    event(player_name: player_name, reason: reason)
  end

  #########################################################
  # SETUP - player order and starting player
  #########################################################

  # OK
  defcommand set_start_player(start_player) when Player.is_id(start_player) do
    [start_player: start_player]
  end

  def start_player_set(start_player, metadata) when Player.is_id(start_player) do
    event(start_player: start_player)
  end

  # OK
  defcommand set_player_order(player_order) when is_list(player_order) do
    for player <- player_order do
      unless Player.is_id(player) do
        raise ArgumentError, "player_order must be a list of integers"
      end
    end

    [player_order: player_order]
  end

  def player_order_set(player_order, metadata) when is_list(player_order) do
    for player_id <- player_order do
      if player_id not in 1..5 do
        raise ArgumentError, "player_order must be a list of integers"
      end
    end

    event(player_order: player_order)
  end

  #########################################################
  # Starting Game
  #########################################################

  # OK
  defcommand start_game() do
    []
  end

  def game_started(metadata) do
    event([])
  end

  def game_start_rejected(reason, metadata) when is_binary(reason) do
    event(reason: reason)
  end

  #########################################################
  # Auctioning - open and close an auction phase
  #########################################################

  defguardp is_phase_number(phase_number) when phase_number in 1..2

  def auction_phase_started(phase_number, start_bidder, metadata)
      when is_phase_number(phase_number) and Player.is_id(start_bidder) do
    event(phase_number: phase_number, start_bidder: start_bidder)
  end

  def auction_phase_ended(phase_number, start_player, metadata)
      when is_phase_number(phase_number) do
    event(phase_number: phase_number, start_player: start_player)
  end

  #########################################################
  # Auctioning - starting player auction turn
  #########################################################

  def player_auction_turn_started(player, company, min_bid, metadata)
      when Player.is_id(player) and Company.is_id(company) and is_integer(min_bid) and
             min_bid >= 8 do
    event(player: player, company: company, min_bid: min_bid)
  end

  #########################################################
  # Auctioning - open and close a company auction
  #########################################################

  @doc """
  Begin the bidding for the first share of a company.

  This can result in either "player_won_company_auction" (a player won the share)
  or "all_players_passed_on_company" (no player bid on the share).
  """
  @spec company_auction_started(Player.id(), Company.id(), Metadata.t()) :: Event.t()
  def company_auction_started(start_bidder, company, metadata)
      when Player.is_id(start_bidder) and Company.is_id(company) do
    event(start_bidder: start_bidder, company: company)
  end

  @doc """
  This and "player_won_company_auction" both end the company auction started by "company_auction_started".
  """
  def all_players_passed_on_company(company, metadata) when Company.is_id(company) do
    event(company: company)
  end

  @doc """
  This and "all_players_passed_on_company" both end the company auction started by "company_auction_started".

  At this point, the company is "Open".
  """
  def player_won_company_auction(auction_winner, company, bid_amount, metadata)
      when Player.is_id(auction_winner) and Company.is_id(company) and is_integer(bid_amount) and
             bid_amount >= 8 do
    event(auction_winner: auction_winner, company: company, bid_amount: bid_amount)
  end

  #########################################################
  # Auctioning - awaiting next player to bid or pass
  #########################################################

  def awaiting_bid_or_pass(player, company, min_bid, metadata)
      when Player.is_id(player) and Company.is_id(company) and is_integer(min_bid) and
             min_bid >= 8 do
    event(player: player, company: company, min_bid: min_bid)
  end

  #########################################################
  # Auctioning - players pass on a company
  #########################################################

  # OK
  defcommand pass_on_company(passing_player, company)
             when Player.is_id(passing_player) and Company.is_id(company) do
    [passing_player: passing_player, company: company]
  end

  def company_passed(passing_player, company, metadata)
      when Player.is_id(passing_player) and Company.is_id(company) do
    event(passing_player: passing_player, company: company)
  end

  def company_pass_rejected(passing_player, company, reason, metadata)
      when Player.is_id(passing_player) and Company.is_id(company) and is_binary(reason) do
    event(passing_player: passing_player, company: company, reason: reason)
  end

  #########################################################
  # Auctioning - players bid on a company
  #########################################################

  # OK
  defcommand submit_bid(bidder, company, amount)
             when Player.is_id(bidder) and Company.is_id(company) and is_integer(amount) do
    [bidder: bidder, company: company, amount: amount]
  end

  def bid_submitted(bidder, company, amount, metadata)
      when Player.is_id(bidder) and Company.is_id(company) and is_integer(amount) do
    event(bidder: bidder, company: company, amount: amount)
  end

  def bid_rejected(bidder, company, amount, reason, metadata)
      when Player.is_id(bidder) and Company.is_id(company) and is_binary(reason) do
    event(bidder: bidder, company: company, amount: amount, reason: reason)
  end

  #########################################################
  # Auctioning - set starting stock price
  #########################################################

  def awaiting_stock_value(player, company, max_price, metadata)
      when Player.is_id(player) and Company.is_id(company) and is_integer(max_price) do
    event(player: player, company: company, max_price: max_price)
  end

  defcommand set_stock_value(auction_winner, company, price)
             when Player.is_id(auction_winner) and Company.is_id(company) and is_integer(price) do
    [auction_winner: auction_winner, company: company, price: price]
  end

  def stock_value_set(auction_winner, company, value, metadata)
      when Player.is_id(auction_winner) and Company.is_id(company) and is_integer(value) do
    event(auction_winner: auction_winner, company: company, value: value)
  end

  def stock_value_rejected(auction_winner, company, price, reason, metadata)
      when Player.is_id(auction_winner) and Company.is_id(company) and is_binary(reason) do
    event(auction_winner: auction_winner, company: company, price: price, reason: reason)
  end

  def stock_value_incremented(company, metadata) when Company.is_id(company) do
    event(company: company)
  end

  #########################################################
  # Player Turn
  #########################################################

  defcommand(:start_player_turn)

  def player_turn_started(player, metadata) when Player.is_id(player) do
    event(player: player)
  end

  def player_turn_rejected(message, metadata) do
    event(message: message)
  end

  def player_turn_ended(player, metadata) when Player.is_id(player) do
    event(player: player)
  end

  #########################################################
  # Player Action Option #1A: Buy Single Stock
  #########################################################

  defcommand purchase_single_stock(purchasing_player, company, price)
             when Player.is_id(purchasing_player) and Company.is_id(company) and is_integer(price) do
    [purchasing_player: purchasing_player, company: company, price: price]
  end

  def single_stock_purchased(purchasing_player, company, price, metadata)
      when Player.is_id(purchasing_player) and Company.is_id(company) and is_integer(price) do
    event(purchasing_player: purchasing_player, company: company, price: price)
  end

  def single_stock_purchase_rejected(purchasing_player, company, price, reason, metadata)
      when Player.is_id(purchasing_player) and Company.is_id(company) and is_integer(price) and
             is_binary(reason) do
    event(purchasing_player: purchasing_player, company: company, price: price, reason: reason)
  end

  #########################################################
  # Player Action Option #3: Pass
  #########################################################

  # OK
  defcommand pass(passing_player) when Player.is_id(passing_player) do
    [passing_player: passing_player]
  end

  def passed(passing_player, metadata) when Player.is_id(passing_player) do
    event(passing_player: passing_player)
  end

  def pass_rejected(passing_player, reason, metadata)
      when Player.is_id(passing_player) and is_binary(reason) do
    event(passing_player: passing_player, reason: reason)
  end

  #########################################################
  # End of Turn Sequence
  #########################################################

  defcommand(:start_interturn)

  # If the timing track is sufficiently advanced, then:
  @simple_event :interturn_started
  # otherwise:
  @simple_event :interturn_skipped

  # If a :interturn_started event has been issued,
  # then when it's finished:
  @simple_event :interturn_ended

  #########################################################
  # Timing Track
  #########################################################

  @simple_event :timing_track_reset
  @simple_event :timing_track_incremented

  #########################################################
  # Dividends
  #########################################################

  # Emitted by Interturn as part of the response to interturn_started.
  defcommand(pay_dividends(), do: [])

  # Emitted and consumed by IncomeTrack
  def paying_dividends(metadata) do
    event([])
  end

  # Emitted by IncomeTrack in response to pay_dividends.
  # It will wait for a corresponding company_dividends_paid event before emitting
  # another for the next company.
  defcommand pay_company_dividends(company, income) do
    [company: company, income: income]
  end

  # Emitted by StockCertificates in response to pay_company_dividends.
  # It also emits money_transferred
  def company_dividends_paid(
        company,
        company_income,
        stock_count,
        certificate_value,
        command_id,
        metadata
      ) do
    event(
      company: company,
      company_income: company_income,
      stock_count: stock_count,
      certificate_value: certificate_value,
      command_id: command_id
    )
  end

  # Emitted by IncomeTrack after last pay_company_dividends/company_dividends_paid cycle.
  # Consumed by Interturn to trigger the next interturn sequence.
  def dividends_paid(metadata) do
    event([])
  end

  #########################################################
  # Message name guards
  # These must remain at the bottom of the module
  #########################################################

  for event_name <- @simple_event do
    def unquote(event_name)(metadata), do: event([])
  end

  def event_names(), do: @event_names
end
