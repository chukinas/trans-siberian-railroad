defmodule TransSiberianRailroad.Auction do
  @moduledoc """
  This module handles all the events and commands related to the auctioning
  of rail companies to players.
  """

  use TypedStruct
  # require Logger
  alias TransSiberianRailroad.Player
  alias TransSiberianRailroad.RailCompany

  typedstruct opaque: true do
    # This is set at the beginning of the game and never changes
    field :player_order, [Player.id()], enforce: true
    # following two are nil anytime we're not in an auction
    field :current_bidder, Player.id()
    # The first company in this list is the one currently being auctioned.
    # When that auction is done, we pop it off the list.
    # When the list is empty, the auction ends.
    field :company_ids, [RailCompany.id()]
  end

  @doc """
  When the game initializes, we're not in an auction yet
  """
  def init(), do: nil

  def handle_event(auctions, event_name, payload)

  def handle_event(nil, "game_started", %{player_order: player_order}) do
    %__MODULE__{
      player_order: player_order,
      current_bidder: nil,
      company_ids: nil
    }
  end

  def handle_event(%__MODULE__{} = auction, "auction_started", %{
        company_ids: company_ids,
        current_bidder: current_bidder
      }) do
    %__MODULE__{auction | company_ids: company_ids, current_bidder: current_bidder}
  end

  def handle_event(auction, _unhandled_message_name, _unhandled_payload) do
    # Logger.warning("#{inspect(__MODULE__)} unhandled event: #{unhandled_message_name}")
    auction
  end

  #########################################################
  # CONVERTERS
  #########################################################

  def in_progress?(nil), do: false
  def in_progress?(%__MODULE__{company_ids: company_ids}), do: is_list(company_ids)

  def current_bidder!(%__MODULE__{current_bidder: current_bidder})
      when is_integer(current_bidder) do
    current_bidder
  end
end
