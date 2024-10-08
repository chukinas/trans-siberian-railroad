defmodule TransSiberianRailroad.Messages do
  @moduledoc """
  This module contains **all** the constructors for `TransSiberianRailroad.Command`
  and `TransSiberianRailroad.Event`.

  ## Notes
  - add defevent and defcommand macros to cut down on boilerplate
  """

  alias TransSiberianRailroad.Aggregator.Players
  alias TransSiberianRailroad.Command
  alias TransSiberianRailroad.RailCompany, as: Company
  alias TransSiberianRailroad.Event
  alias TransSiberianRailroad.Player

  # TODO
  @type metadata() :: term()

  #########################################################
  # Initializing Game
  #########################################################

  def initialize_game() do
    game_id =
      1..6
      |> Enum.map(fn _ -> Enum.random(?A..?Z) end)
      |> Enum.join()

    %Command{
      name: "initialize_game",
      payload: %{game_id: game_id}
    }
  end

  def game_initialized(game_id, metadata) when is_binary(game_id) do
    Event.new("game_initialized", %{game_id: game_id}, metadata)
  end

  #########################################################
  # Adding Players
  #########################################################

  def add_player(player_name) when is_binary(player_name) do
    %Command{
      name: "add_player",
      payload: %{player_name: player_name}
    }
  end

  def player_added(player_id, player_name, metadata)
      when is_integer(player_id) and is_binary(player_name) do
    Event.new("player_added", %{player_id: player_id, player_name: player_name}, metadata)
  end

  def player_rejected(reason, metadata) when is_binary(reason) do
    Event.new("player_rejected", %{reason: reason}, metadata)
  end

  #########################################################
  # SETUP - player order and starting player
  #########################################################

  def start_player_selected(player_id, metadata) when is_integer(player_id) do
    Event.new("start_player_selected", %{player_id: player_id}, metadata)
  end

  #########################################################
  # Starting Game
  #########################################################

  def start_game(player_id) when is_integer(player_id) do
    %Command{
      name: "start_game",
      payload: %{player_id: player_id}
    }
  end

  # TODO rename player_id to something more descriptive.
  # It only matters because we want a record of the player who "pressed the start button".
  # It's not about the player who goes first.
  def game_started(player_id, player_order, metadata)
      when is_integer(player_id) and length(player_order) in 3..5 do
    for player_id <- player_order do
      if player_id not in 1..5 do
        raise ArgumentError, "player_order must be a list of integers"
      end
    end

    Event.new(
      "game_started",
      %{
        player_id: player_id,
        player_order: player_order,
        starting_money: Players.starting_money(length(player_order))
      },
      metadata
    )
  end

  def game_not_started(reason, metadata) when is_binary(reason) do
    Event.new("game_not_started", %{reason: reason}, metadata)
  end

  #########################################################
  # Auctioning - open and close an auction phase
  #########################################################

  def auction_phase_started(phase_number, starting_bidder, metadata)
      when phase_number in 1..2 and starting_bidder in 1..5 do
    Event.new(
      "auction_phase_started",
      %{phase_number: phase_number, starting_bidder: starting_bidder},
      metadata
    )
  end

  def auction_phase_ended(phase_number, metadata) do
    Event.new("auction_phase_ended", %{phase_number: phase_number}, metadata)
  end

  #########################################################
  # Auctioning - open and close a company auction
  #########################################################

  @doc """
  Begin the bidding for the first share of a company.

  This can result in either "company_opened" (a player won the share)
  or "company_not_opened" (no player bid on the share).
  """
  @spec company_auction_started(Player.id(), Company.id(), metadata()) :: Event.t()
  def company_auction_started(starting_bidder, company, metadata) do
    Event.new(
      "company_auction_started",
      %{starting_bidder: starting_bidder, company: company},
      metadata
    )
  end

  # TODO add is_company guard
  @doc """
  This and "company_opened" both end the company auction started by "company_auction_started".
  """
  def company_not_opened(company_id, metadata) when is_atom(company_id) do
    Event.new("company_not_opened", %{company_id: company_id}, metadata)
  end

  # TODO add is_player guard
  @doc """
  This and "company_not_opened" both end the company auction started by "company_auction_started".
  """
  def company_opened(company_id, player_id, bid_amount, metadata)
      when is_atom(company_id) and is_integer(bid_amount) and bid_amount >= 8 do
    Event.new(
      "company_opened",
      %{company_id: company_id, player_id: player_id, bid_amount: bid_amount},
      metadata
    )
  end

  #########################################################
  # Auctioning - players pass on a company
  #########################################################

  def pass_on_company(player_id, company_id) when is_integer(player_id) and is_atom(company_id) do
    %Command{
      name: "pass_on_company",
      payload: %{player_id: player_id, company_id: company_id}
    }
  end

  # TODO replace is_atom with a more specific guard
  def company_passed(player_id, company_id, metadata)
      when is_integer(player_id) and is_atom(company_id) do
    Event.new("company_passed", %{player_id: player_id, company_id: company_id}, metadata)
  end

  def company_pass_rejected(player_id, company_id, reason, metadata)
      when is_integer(player_id) and is_atom(company_id) and is_binary(reason) do
    Event.new(
      "company_pass_rejected",
      %{player_id: player_id, company_id: company_id, reason: reason},
      metadata
    )
  end

  #########################################################
  # Auctioning - players bid on a company
  #########################################################

  # TODO rename company_bid
  # TODO add :amount field
  def company_bid(player_id, company_id, metadata)
      when is_integer(player_id) and is_atom(company_id) do
    Event.new("company_bid", %{player_id: player_id, company_id: company_id}, metadata)
  end
end
