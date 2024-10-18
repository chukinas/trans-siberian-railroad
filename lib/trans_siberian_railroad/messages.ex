defmodule TransSiberianRailroad.Messages do
  @moduledoc """
  This module contains **all** the constructors for `TransSiberianRailroad.Command`
  and `TransSiberianRailroad.Event`.

  ## Notes
  - add defevent and defcommand macros to cut down on boilerplate
  - TODO: somehow make the event metadata optional?
  """

  require TransSiberianRailroad.Metadata, as: Metadata
  require TransSiberianRailroad.Player, as: Player
  require TransSiberianRailroad.RailCompany, as: Company
  alias TransSiberianRailroad.Event

  # TODO
  @type metadata() :: term()

  #########################################################
  # - Local boilerplate reduction
  # - Accumulate command and event names
  #   in order to validate then in aggregators
  #########################################################

  Module.register_attribute(__MODULE__, :command_names, accumulate: true)
  Module.register_attribute(__MODULE__, :event_names, accumulate: true)

  defmacrop command(fields) do
    # TODO accumulate command names
    quote do
      name =
        with {name, _arity} = __ENV__.function do
          to_string(name)
        end

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
  #########################################################

  @type entity() :: Player.id() | Company.id() | :bank
  @type amount() :: integer()
  @spec money_transferred(%{entity() => amount()}, String.t(), metadata()) :: Event.t()
  def money_transferred(%{} = transfers, reason, metadata)
      when is_binary(reason) and Metadata.is(metadata) do
    # TODO validate the transfers
    # 0 = transfers |> Map.values() |> Enum.sum()
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

  def game_initialized(game_id, metadata) when is_binary(game_id) do
    event(game_id: game_id)
  end

  #########################################################
  # Adding Players
  #########################################################

  def add_player(player_name) when is_binary(player_name) do
    command(player_name: player_name)
  end

  def player_added(player_id, player_name, metadata)
      when is_integer(player_id) and is_binary(player_name) do
    event(player_id: player_id, player_name: player_name)
  end

  def player_rejected(reason, metadata) when is_binary(reason) do
    event(reason: reason)
  end

  #########################################################
  # SETUP - player order and starting player
  #########################################################

  # TODO unify the language
  # starting_player -> start_player
  # set or selected
  def set_start_player(starting_player) when is_integer(starting_player) do
    command(starting_player: starting_player)
  end

  def start_player_selected(start_player, metadata) when is_integer(start_player) do
    event(start_player: start_player)
  end

  def set_player_order(player_order) when is_list(player_order) do
    command(player_order: player_order)
  end

  # TODO replace set with selected?
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

  def start_game(player_id) when is_integer(player_id) do
    command(player_id: player_id)
  end

  # TODO rename player_id to something more descriptive.
  # It only matters because we want a record of the player who "pressed the start button".
  # It's not about the player who goes first.
  # This bit of data belongs in the metadata instead.
  def game_started(player_id, starting_money, metadata) when is_integer(player_id) do
    event(player_id: player_id, starting_money: starting_money)
  end

  def game_not_started(reason, metadata) when is_binary(reason) do
    event(reason: reason)
  end

  #########################################################
  # Auctioning - open and close an auction phase
  #########################################################

  def auction_phase_started(phase_number, starting_bidder, metadata)
      when phase_number in 1..2 and starting_bidder in 1..5 do
    event(phase_number: phase_number, starting_bidder: starting_bidder)
  end

  def auction_phase_ended(phase_number, metadata) do
    event(phase_number: phase_number)
  end

  #########################################################
  # Auctioning - open and close a company auction
  #########################################################

  @doc """
  Begin the bidding for the first share of a company.

  This can result in either "company_opened" (a player won the share)
  or "all_players_passed_on_company" (no player bid on the share).
  """
  @spec company_auction_started(Player.id(), Company.id(), metadata()) :: Event.t()
  def company_auction_started(starting_bidder, company, metadata) do
    event(starting_bidder: starting_bidder, company: company)
  end

  @doc """
  This and "company_opened" both end the company auction started by "company_auction_started".
  """
  def all_players_passed_on_company(company, metadata) when Company.is_id(company) do
    event(company: company)
  end

  # TODO add is_player guard
  @doc """
  This and "all_players_passed_on_company" both end the company auction started by "company_auction_started".
  """
  def company_opened(company_id, player_id, bid_amount, metadata)
      when is_atom(company_id) and is_integer(bid_amount) and bid_amount >= 8 do
    event(company_id: company_id, player_id: player_id, bid_amount: bid_amount)
  end

  #########################################################
  # Auctioning - players pass on a company
  #########################################################

  def pass_on_company(player_id, company_id) when is_integer(player_id) and is_atom(company_id) do
    command(player_id: player_id, company_id: company_id)
  end

  # TODO replace is_atom with a more specific guard
  def company_passed(player_id, company_id, metadata)
      when is_integer(player_id) and is_atom(company_id) do
    event(player_id: player_id, company_id: company_id)
  end

  def company_pass_rejected(player_id, company_id, reason, metadata)
      when is_integer(player_id) and is_atom(company_id) and is_binary(reason) do
    event(player_id: player_id, company_id: company_id, reason: reason)
  end

  #########################################################
  # Auctioning - players bid on a company
  #########################################################

  def submit_bid(player_id, company_id, amount)
      when Player.is_id(player_id) and Company.is_id(company_id) and is_integer(amount) do
    command(player_id: player_id, company_id: company_id, amount: amount)
  end

  def bid_rejected(player_id, company_id, amount, reason, metadata)
      when Player.is_id(player_id) and Company.is_id(company_id) and is_binary(reason) do
    event(player_id: player_id, company_id: company_id, amount: amount, reason: reason)
  end

  # TODO rename company_bid
  # TODO add :amount field
  def company_bid(player_id, company_id, amount, metadata)
      when Player.is_id(player_id) and Company.is_id(company_id) and is_integer(amount) do
    event(player_id: player_id, company_id: company_id, amount: amount)
  end

  #########################################################
  # Auctioning - set starting stock price
  #########################################################

  def set_starting_stock_price(bidder, company_id, price)
      when Player.is_id(bidder) and is_atom(company_id) and is_integer(price) do
    command(player_id: bidder, company_id: company_id, price: price)
  end

  def starting_stock_price_set(player_id, company_id, price, metadata)
      when Player.is_id(player_id) and Company.is_id(company_id) and is_integer(price) do
    event(player_id: player_id, company_id: company_id, price: price)
  end

  def starting_stock_price_rejected(player_id, company_id, price, reason, metadata)
      when Player.is_id(player_id) and Company.is_id(company_id) and is_binary(reason) do
    event(player_id: player_id, company_id: company_id, price: price, reason: reason)
  end

  #########################################################
  # Message name guards
  # These must remain at the bottom of the module
  #########################################################

  def valid_command_name?(name), do: name in @command_names
  def valid_event_name?(name), do: name in @event_names

  def event_names(), do: @event_names

  # defguard is_command_name(name) when name in @command_names
  # defguard is_event_name(name) when name in @event_names
end
