defmodule TransSiberianRailroad.Messages do
  @moduledoc """
  This module contains **all** the constructors for `TransSiberianRailroad.Command`
  and `TransSiberianRailroad.Event`.
  """

  alias TransSiberianRailroad.Command
  alias TransSiberianRailroad.Event
  alias TransSiberianRailroad.Players

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

  def game_initialized(game_id) when is_binary(game_id) do
    %Event{
      name: "game_initialized",
      payload: %{game_id: game_id}
    }
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

  def player_added(player_id, player_name)
      when is_integer(player_id) and is_binary(player_name) do
    %Event{
      name: "player_added",
      payload: %{player_id: player_id, player_name: player_name}
    }
  end

  def player_rejected(reason) when is_binary(reason) do
    %Event{
      name: "player_rejected",
      payload: %{reason: reason}
    }
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

  def game_started(player_id, player_order)
      when is_integer(player_id) and length(player_order) in 3..5 do
    for player_id <- player_order do
      if player_id not in 1..5 do
        raise ArgumentError, "player_order must be a list of integers"
      end
    end

    %Event{
      name: "game_started",
      payload: %{
        player_id: player_id,
        player_order: player_order,
        starting_money: Players.starting_money(length(player_order))
      }
    }
  end

  def game_not_started(reason) when is_binary(reason) do
    %Event{
      name: "game_not_started",
      payload: %{reason: reason}
    }
  end

  #########################################################
  # Auctioning
  #########################################################

  def auction_started(current_bidder, company_ids)
      when is_integer(current_bidder) and is_list(company_ids) do
    %Event{
      name: "auction_started",
      payload: %{current_bidder: current_bidder, company_ids: company_ids}
    }
  end

  #########################################################
  # Ending Game
  #########################################################

  def game_ended() do
    %Event{
      name: "game_ended"
    }
  end
end
