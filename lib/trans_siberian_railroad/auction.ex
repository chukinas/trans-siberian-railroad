defmodule TransSiberianRailroad.Auction do
  @moduledoc """
  This module handles all the events and commands related to the auctioning
  of rail companies to players.
  """

  alias TransSiberianRailroad.Event
  alias TransSiberianRailroad.Messages
  alias TransSiberianRailroad.Player
  alias TransSiberianRailroad.RailCompany

  @opaque t() :: %{
            optional(:last_version) => non_neg_integer(),
            optional(:player_order) => [Player.id(), ...],
            optional(:current_auction_phase) => %{
              required(:starting_bidder) => Player.id(),
              required(:remaining_company_ids) => [RailCompany.id()],
              optional(:current_auction) => %{
                required(:company_id) => RailCompany.id(),
                required(:bidders) => Player.id()
              }
            }
          }

  #########################################################
  # CONSTRUCTORS
  #########################################################

  @doc """
  When the game initializes, we're not in an auction yet
  """
  def init(), do: %{}

  def state(events) do
    events = Event.sort(events)

    auction =
      Enum.reduce(events, init(), fn event, auction ->
        %Event{
          name: event_name,
          payload: payload,
          sequence_number: sequence_number
        } = event

        auction
        |> Map.put(:last_version, sequence_number)
        |> handle_event(event_name, payload)
      end)

    {auction, []}
  end

  #########################################################
  # REDUCERS (command handlers)
  #########################################################

  def handle_command(auction, command_name, payload)

  # TODO I don't like all these function clauses are public.
  # TODO I don't like the name of this command.
  # TODO rename player_id to something like 'passing player'
  # TODO test that if the company and player don't match the current ones,
  # a rejection event is generated.
  def handle_command(auction, "pass_on_company", payload) do
    %{player_id: player_id, company_id: company_id} = payload
    metadata = [sequence_number: auction.last_version + 1]
    current_bidder = current_bidder!(auction)

    cond do
      !in_progress?(auction) ->
        Messages.company_pass_rejected(
          payload.player_id,
          payload.company_id,
          "There is no auction in progress.",
          metadata
        )

      player_id != current_bidder ->
        Messages.company_pass_rejected(
          payload.player_id,
          payload.company_id,
          "It's player #{current_bidder}'s turn to bid on a company.",
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

    # TODO current_bidder! shouldn't be used here. I need a function that won't raise.
    # TODO write a test that checks that the index always increases by 1.
  end

  #########################################################
  # REDUCERS (event handlers)
  #########################################################

  # TODO temp
  require Logger
  # TODO should be private. Otherwise :last_version will have problems.
  def handle_event(auctions, event_name, payload)

  def handle_event(auction, "game_started", payload) do
    Map.put(auction, :player_order, payload.player_order)
  end

  def handle_event(auction, "auction_started", payload) do
    current_auction_phase = %{
      starting_bidder: payload.current_bidder,
      remaining_company_ids: payload.company_ids
    }

    Map.put(auction, :current_auction_phase, current_auction_phase)
  end

  # TODO add a test to check the current company being bid
  def handle_event(auction, "company_passed", _payload) do
    update_in(auction, [:current_auction_phase, :current_auction, :bidders], &Enum.drop(&1, 1))
  end

  def handle_event(auction, _unhandled_message_name, _unhandled_payload) do
    # Logger.warning("#{inspect(__MODULE__)} unhandled event: #{unhandled_message_name}")
    auction
  end

  #########################################################
  # CONVERTERS
  #########################################################

  def in_progress?(auction) do
    !!auction[:current_auction_phase]
  end

  def current_bidder!(auction) do
    case get_in(auction, [:current_auction_phase, :current_auction, :bidders, Access.at(0)]) do
      player_id when is_integer(player_id) -> player_id
      _ -> raise "No current bidder"
    end
  end

  def get_current_company(auction) do
    get_in(auction, [:current_auction_phase, :current_auction, :company_id])
  end
end
