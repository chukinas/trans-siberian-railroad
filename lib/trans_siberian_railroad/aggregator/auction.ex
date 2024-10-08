defmodule TransSiberianRailroad.Aggregator.Auction do
  @moduledoc """
  This module handles all the events and commands related to the auctioning
  of rail companies to players.
  """

  use TypedStruct
  use TransSiberianRailroad.Aggregator
  require TransSiberianRailroad.RailCompany, as: Company
  alias TransSiberianRailroad.Aggregator.Players
  alias TransSiberianRailroad.Event
  alias TransSiberianRailroad.Messages
  alias TransSiberianRailroad.Metadata
  alias TransSiberianRailroad.Player

  typedstruct opaque: true do
    field :last_version, non_neg_integer()

    # game_started SETS true
    field :game_started, boolean(), default: false

    # game_started.player_order SETS
    field :player_order, [Player.id()]

    # auction_phase_started.phase_number SETS
    # auction_phase_ended CLEARS
    field :phase_number, 1..2

    # auction_phase_started.starting_bidder SETS
    # auction_phase_ended CLEARS
    field :phase_starting_bidder, 1..5

    # company_not_opened    INCREMENTS
    # company_opened        INCREMENTS
    # auction_phase_ended   SETS 0
    field :phase_count_company_auctions_ended, 0..4, default: 0

    # company_auction_started.company_id SETS
    # company_not_opened CLEARS
    # company_opened     CLEARS
    field :company, Company.id()

    # These are the players still in the bidding for the company's share.
    # As players pass, they are removed from this list.
    # The first player in the list is the current bidder.
    # company_auction_started.starting_bidder + :player_order SETS
    # company_bid MOVES the first player to end of list
    # company_passed REMOVES the first player
    # company_not_opened CLEARS
    # company_opened     CLEARS
    field :bidders, [Player.id()]
  end

  #########################################################
  # CONSTRUCTORS
  #########################################################

  @impl true
  @doc """
  When the game initializes, we're not in an auction yet
  """
  def init(), do: %__MODULE__{}

  #########################################################
  # REDUCERS
  #########################################################

  @impl true
  def put_version(auction, version) do
    Map.put(auction, :last_version, version)
  end

  #########################################################
  # REDUCERS (command handlers)
  #########################################################

  @spec handle_command(t(), String.t(), map()) :: Event.t()
  defp handle_command(auction, "pass_on_company", payload) do
    %{player_id: player_id, company_id: company_id} = payload
    metadata = Metadata.from_aggregator(auction)
    maybe_current_bidder = get_current_bidder(auction)

    cond do
      !in_progress?(auction) ->
        Messages.company_pass_rejected(
          payload.player_id,
          payload.company_id,
          "There is no auction in progress.",
          metadata
        )

      player_id != maybe_current_bidder ->
        Messages.company_pass_rejected(
          payload.player_id,
          payload.company_id,
          "It's player #{maybe_current_bidder}'s turn to bid on a company.",
          metadata
        )

      company_id != get_current_company(auction) ->
        Messages.company_pass_rejected(
          payload.player_id,
          payload.company_id,
          "The company you're trying to pass on isn't the one being auctioned.",
          metadata
        )

      true ->
        Messages.company_passed(player_id, company_id, metadata)
    end
  end

  #########################################################
  # REDUCERS (event handlers)
  #########################################################

  defp handle_event(auction, "game_started", payload) do
    %__MODULE__{auction | game_started: true, player_order: payload.player_order}
  end

  defp handle_event(auction, "auction_phase_started", payload) do
    %__MODULE__{
      auction
      | phase_number: payload.phase_number,
        phase_starting_bidder: payload.starting_bidder
    }
  end

  defp handle_event(auction, "auction_phase_ended", _payload) do
    %__MODULE__{
      auction
      | phase_number: nil,
        phase_starting_bidder: nil,
        phase_count_company_auctions_ended: 0
    }
  end

  defp handle_event(auction, "company_auction_started", payload) do
    bidders =
      Players.player_order_once_around_the_table(auction.player_order, payload.starting_bidder)

    %__MODULE__{auction | company: payload.company, bidders: bidders}
  end

  defp handle_event(auction, "company_passed", _payload) do
    bidders = Enum.drop(auction.bidders, 1)
    %__MODULE__{auction | bidders: bidders}
  end

  defp handle_event(auction, event_name, _payload)
       when event_name in ["company_not_opened", "company_opened"] do
    %__MODULE__{
      auction
      | company: nil,
        bidders: nil,
        phase_count_company_auctions_ended: auction.phase_count_company_auctions_ended + 1
    }
  end

  defp handle_event(auction, "company_bid", _payload) do
    bidders =
      with [current_bidder | rest] <- auction.bidders do
        rest ++ [current_bidder]
      end

    %__MODULE__{auction | bidders: bidders}
  end

  #########################################################
  # CONVERTERS (projection -> events)
  #########################################################

  def events_from_projection(auction) do
    [
      &maybe_start_company_auction/1,
      &maybe_not_open_company/1
    ]
    |> Enum.find_value(& &1.(auction))
  end

  defp maybe_start_company_auction(%__MODULE__{} = auction) do
    phase_number = auction.phase_number

    if !!phase_number and !auction.company do
      starting_bidder =
        case auction.phase_count_company_auctions_ended do
          _ -> auction.phase_starting_bidder
        end

      company =
        Company.ids(phase_number)
        |> Enum.drop(auction.phase_count_company_auctions_ended)
        |> hd

      metadata = Metadata.from_aggregator(auction)
      Messages.company_auction_started(starting_bidder, company, metadata)
    end
  end

  defp maybe_not_open_company(auction) do
    with {:ok, company} <- fetch_company(auction),
         true <- all_players_passed_on_company?(auction) do
      metadata = Metadata.from_aggregator(auction)
      Messages.company_not_opened(company, metadata)
    else
      _ -> nil
    end
  end

  #########################################################
  # CONVERTERS
  #########################################################

  defp all_players_passed_on_company?(%__MODULE__{bidders: bidders}) do
    bidders == []
  end

  def in_progress?(auction) do
    !!auction.phase_number
  end

  def fetch_current_bidder(auction) do
    case get_current_bidder(auction) do
      nil -> :error
      current_bidder -> {:ok, current_bidder}
    end
  end

  def get_current_bidder(auction) do
    case auction.bidders do
      [current_bidder | _] -> current_bidder
      _ -> nil
    end
  end

  defp fetch_company(auction) do
    maybe_company = auction.company

    if Company.is_id(maybe_company) do
      {:ok, maybe_company}
    else
      :error
    end
  end

  def get_current_company(auction) do
    auction.company
  end
end
