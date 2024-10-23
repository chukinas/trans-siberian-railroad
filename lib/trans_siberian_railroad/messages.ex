defmodule TransSiberianRailroad.Messages do
  @moduledoc """
  This module contains **all** the constructors for `TransSiberianRailroad.Command`
  and `TransSiberianRailroad.Event`.
  """

  require TransSiberianRailroad.Metadata, as: Metadata
  require TransSiberianRailroad.Player, as: Player
  require TransSiberianRailroad.RailCompany, as: Company
  alias TransSiberianRailroad.Event

  #########################################################
  # - Local boilerplate reduction
  # - Accumulate command and event names
  #   in order to validate then in aggregators
  #########################################################

  Module.register_attribute(__MODULE__, :command_names, accumulate: true)
  Module.register_attribute(__MODULE__, :event_names, accumulate: true)

  defmacrop command(fields) do
    name =
      with {name, _arity} = __CALLER__.function do
        to_string(name)
      end

    Module.put_attribute(__MODULE__, :command_names, name)

    quote do
      name = unquote(name)
      payload = Map.new(unquote(fields))
      %TransSiberianRailroad.Command{name: name, payload: payload}
    end
  end

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
  # Money
  # Moving money between players, bank, and companies is
  # such a common operation that it's all handled via this
  # single event.
  # This is one of the few (only?) messages that can be
  # issued by any Aggregator.
  #########################################################

  @type entity() :: Player.id() | Company.id() | :bank
  @type amount() :: integer()
  @spec money_transferred(%{entity() => amount()}, String.t(), Metadata.t()) :: Event.t()
  def money_transferred(%{} = transfers, reason, metadata)
      when is_binary(reason) and Metadata.is(metadata) do
    0 = transfers |> Map.values() |> Enum.sum()
    event(transfers: transfers, reason: reason)
  end

  #########################################################
  # Initializing Game
  #########################################################

  def initialize_game() do
    game_id =
      1..6
      |> Enum.map(fn _ -> Enum.random(?A..?Z) end)
      |> Enum.join()

    command(game_id: game_id)
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

  def add_player(player_name) when is_binary(player_name) do
    command(player_name: player_name)
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

  def set_start_player(start_player) when Player.is_id(start_player) do
    command(start_player: start_player)
  end

  def start_player_set(start_player, metadata) when Player.is_id(start_player) do
    event(start_player: start_player)
  end

  def set_player_order(player_order) when is_list(player_order) do
    for player <- player_order do
      unless Player.is_id(player) do
        raise ArgumentError, "player_order must be a list of integers"
      end
    end

    command(player_order: player_order)
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

  def start_game() do
    command([])
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

  def auction_phase_ended(phase_number, metadata) when is_phase_number(phase_number) do
    event(phase_number: phase_number)
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
  # Auctioning - players pass on a company
  #########################################################

  def pass_on_company(passing_player, company)
      when Player.is_id(passing_player) and Company.is_id(company) do
    command(passing_player: passing_player, company: company)
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

  def submit_bid(bidder, company, amount)
      when Player.is_id(bidder) and Company.is_id(company) and is_integer(amount) do
    command(bidder: bidder, company: company, amount: amount)
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

  def set_starting_stock_price(auction_winner, company, price)
      when Player.is_id(auction_winner) and Company.is_id(company) and is_integer(price) do
    command(auction_winner: auction_winner, company: company, price: price)
  end

  def starting_stock_price_set(auction_winner, company, price, metadata)
      when Player.is_id(auction_winner) and Company.is_id(company) and is_integer(price) do
    event(auction_winner: auction_winner, company: company, price: price)
  end

  def starting_stock_price_rejected(auction_winner, company, price, reason, metadata)
      when Player.is_id(auction_winner) and Company.is_id(company) and is_binary(reason) do
    event(auction_winner: auction_winner, company: company, price: price, reason: reason)
  end

  #########################################################
  # Player Turn
  #########################################################

  def player_turn_started(player, metadata) when Player.is_id(player) do
    event(player: player)
  end

  #########################################################
  # Player Action Option #1A: Buy Single Stock
  #########################################################

  def purchase_single_stock(purchasing_player, company, price)
      when Player.is_id(purchasing_player) and Company.is_id(company) and is_integer(price) do
    command(purchasing_player: purchasing_player, company: company, price: price)
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

  def pass(passing_player) when Player.is_id(passing_player) do
    command(passing_player: passing_player)
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

  def end_of_turn_sequence_started(metadata) do
    event([])
  end

  #########################################################
  # Message name guards
  # These must remain at the bottom of the module
  #########################################################

  def command_names(), do: @command_names
  def event_names(), do: @event_names
end
