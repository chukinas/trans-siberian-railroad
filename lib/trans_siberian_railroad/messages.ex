defmodule TransSiberianRailroad.Messages do
  @moduledoc """
  This module contains **all** the constructors for `TransSiberianRailroad.Command`
  and `TransSiberianRailroad.Event`.
  """

  alias TransSiberianRailroad.Aggregator.Players
  alias TransSiberianRailroad.Command
  alias TransSiberianRailroad.Event

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
  # Starting Game
  #########################################################

  def start_game(player_id) when is_integer(player_id) do
    %Command{
      name: "start_game",
      payload: %{player_id: player_id}
    }
  end

  def start_player_selected(player_id, metadata) when is_integer(player_id) do
    Event.new("start_player_selected", %{player_id: player_id}, metadata)
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
  # Auctioning
  #########################################################

  # TODO rename auction_phase_started
  # or phase_1_auction_started
  # Which would require a later phase_2_auction_started.
  # Or maybe it's just one event that has a :phase payload field.
  # Either way, I need to distinguish between the auction phase as a whole,
  # and the auctioning of individual company first shares.
  def auction_started(current_bidder, company_ids, metadata)
      when is_integer(current_bidder) and is_list(company_ids) do
    Event.new(
      "auction_started",
      %{current_bidder: current_bidder, company_ids: company_ids},
      metadata
    )
  end

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
  # Ending Game
  #########################################################

  def game_ended(metadata) do
    Event.new("game_ended", %{}, metadata)
  end
end
