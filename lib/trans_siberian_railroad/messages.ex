defmodule TransSiberianRailroad.Messages do
  @moduledoc """
  This module contains **all** the constructors for `TransSiberianRailroad.Command`
  and `TransSiberianRailroad.Event`.

  The messages described in this file **completely** describe the game's player actions and events (found in rulebook.pdf).
  """

  use TransSiberianRailroad.Command
  use TransSiberianRailroad.Event
  require TransSiberianRailroad.Metadata, as: Metadata
  require TransSiberianRailroad.Constants, as: Constants
  alias Ecto.Changeset
  alias TransSiberianRailroad.Event

  #########################################################
  # "Broad Events"
  # Unlike all the other events, these two events may
  # be issued by **any** aggregator.
  #########################################################

  @type entity() :: Constants.player() | Constants.company() | :bank

  # Money
  # Moving money between players, bank, and companies is
  # such a common operation that it's all handled via this
  # single event.
  # This is one of the few (only?) messages that can be
  # issued by any Aggregator.
  @type amount() :: integer()
  @spec money_transferred(%{entity() => amount()}, String.t(), Metadata.t()) :: Event.t()
  defevent money_transferred(%{} = transfers, reason) when is_binary(reason) do
    0 = transfers |> Map.values() |> Enum.sum()
    [transfers: transfers, reason: reason]
  end

  @spec stock_certificates_transferred(
          Constants.company(),
          entity(),
          entity(),
          pos_integer(),
          String.t(),
          Metadata.t()
        ) ::
          Event.t()
  defevent stock_certificates_transferred(company, from, to, quantity, reason)
           when quantity in 1..5 do
    [company: company, from: from, to: to, quantity: quantity, reason: reason]
  end

  ##########################################################
  # Initializing Game
  #########################################################

  defcommand initialize_game() do
    game_id =
      1..6
      |> Enum.map(fn _ -> Enum.random(?A..?Z) end)
      |> Enum.join()

    [game_id: game_id]
  end

  defevent game_initialized(game_id) do
    [game_id: game_id]
  end

  defevent game_initialization_rejected(game_id, reason) do
    [game_id: game_id, reason: reason]
  end

  #########################################################
  # Adding Players
  #########################################################

  defcommand add_player(player_name) when is_binary(player_name) do
    [player_name: player_name]
  end

  defevent player_added(player_id, player_name)
           when Constants.is_player(player_id) and is_binary(player_name) do
    [player_id: player_id, player_name: player_name]
  end

  defevent player_rejected(player_name, reason) when is_binary(reason) do
    [player_name: player_name, reason: reason]
  end

  #########################################################
  # SETUP - player order and starting player
  #########################################################

  defcommand set_start_player(start_player) when Constants.is_player(start_player) do
    [start_player: start_player]
  end

  defevent start_player_set(start_player) when Constants.is_player(start_player) do
    [start_player: start_player]
  end

  defcommand set_player_order(player_order) when is_list(player_order) do
    for player <- player_order do
      unless Constants.is_player(player) do
        raise ArgumentError, "player_order must be a list of integers"
      end
    end

    [player_order: player_order]
  end

  defevent player_order_set(player_order) when is_list(player_order) do
    for player_id <- player_order do
      if player_id not in 1..5 do
        raise ArgumentError, "player_order must be a list of integers"
      end
    end

    [player_order: player_order]
  end

  #########################################################
  # Starting Game
  #########################################################

  defcommand start_game() do
    []
  end

  defevent game_started() do
    []
  end

  defevent game_start_rejected(reason) when is_binary(reason) do
    [reason: reason]
  end

  #########################################################
  # Auctioning - open and close an auction phase
  #########################################################

  defguardp is_phase_number(phase_number) when phase_number in 1..2

  defevent auction_phase_started(phase_number, start_bidder)
           when is_phase_number(phase_number) and Constants.is_player(start_bidder) do
    [phase_number: phase_number, start_bidder: start_bidder]
  end

  defevent auction_phase_ended(phase_number, start_player)
           when is_phase_number(phase_number) do
    [phase_number: phase_number, start_player: start_player]
  end

  #########################################################
  # Auctioning - starting player auction turn
  #########################################################

  defevent player_auction_turn_started(player, company, min_bid)
           when Constants.is_player(player) and Constants.is_company(company) and
                  is_integer(min_bid) and
                  min_bid >= 8 do
    [player: player, company: company, min_bid: min_bid]
  end

  #########################################################
  # Auctioning - open and close a company auction
  #########################################################

  @doc """
  Begin the bidding for the first share of a company.

  This can result in either "player_won_company_auction" (a player won the share)
  or "all_players_passed_on_company" (no player bid on the share).
  """
  defevent company_auction_started(start_bidder, company)
           when Constants.is_player(start_bidder) and Constants.is_company(company) do
    [start_bidder: start_bidder, company: company]
  end

  @doc """
  This and "player_won_company_auction" both end the company auction started by "company_auction_started".
  """
  defevent all_players_passed_on_company(company) when Constants.is_company(company) do
    [company: company]
  end

  @doc """
  This and "all_players_passed_on_company" both end the company auction started by "company_auction_started".

  At this point, the company is "Open".
  """
  defevent player_won_company_auction(auction_winner, company, bid_amount)
           when Constants.is_player(auction_winner) and Constants.is_company(company) and
                  is_integer(bid_amount) and
                  bid_amount >= 8 do
    [auction_winner: auction_winner, company: company, bid_amount: bid_amount]
  end

  defevent company_auction_ended(company) when Constants.is_company(company) do
    [company: company]
  end

  #########################################################
  # Auctioning - awaiting next player to bid or pass
  #########################################################

  defevent awaiting_bid_or_pass(player, company, min_bid)
           when Constants.is_player(player) and Constants.is_company(company) and
                  is_integer(min_bid) and
                  min_bid >= 8 do
    [player: player, company: company, min_bid: min_bid]
  end

  #########################################################
  # Auctioning - players pass on a company
  #########################################################

  defcommand pass_on_company(passing_player, company)
             when Constants.is_player(passing_player) and Constants.is_company(company) do
    [passing_player: passing_player, company: company]
  end

  defevent company_passed(passing_player, company)
           when Constants.is_player(passing_player) and Constants.is_company(company) do
    [passing_player: passing_player, company: company]
  end

  defevent company_pass_rejected(passing_player, company, reason)
           when Constants.is_player(passing_player) and Constants.is_company(company) and
                  is_binary(reason) do
    [passing_player: passing_player, company: company, reason: reason]
  end

  #########################################################
  # Auctioning - players bid on a company
  #########################################################

  defcommand submit_bid(bidder, company, amount)
             when Constants.is_player(bidder) and Constants.is_company(company) and
                    is_integer(amount) do
    [bidder: bidder, company: company, amount: amount]
  end

  defevent bid_submitted(bidder, company, amount)
           when Constants.is_player(bidder) and Constants.is_company(company) and
                  is_integer(amount) do
    [bidder: bidder, company: company, amount: amount]
  end

  defevent bid_rejected(bidder, company, amount, reason)
           when Constants.is_player(bidder) and Constants.is_company(company) and
                  is_binary(reason) do
    [bidder: bidder, company: company, amount: amount, reason: reason]
  end

  #########################################################
  # Auctioning - initial rail link
  #########################################################

  defevent awaiting_initial_rail_link(player, company, available_links) do
    [player: player, company: company, available_links: available_links]
  end

  defcommand build_initial_rail_link(player, company, rail_link)
             when Constants.is_player(player) and Constants.is_company(company) and
                    is_list(rail_link) do
    [player: player, company: company, rail_link: rail_link]
  end

  defevent initial_rail_link_rejected(player, company, rail_link, reason)
           when Constants.is_player(player) and Constants.is_company(company) and
                  is_binary(reason) do
    [player: player, company: company, rail_link: rail_link, reason: reason]
  end

  defevent initial_rail_link_built(player, company, rail_link, link_income)
           when Constants.is_player(player) and Constants.is_company(company) and
                  is_list(rail_link) and is_integer(link_income) and link_income > 0 do
    [player: player, company: company, rail_link: rail_link, link_income: link_income]
  end

  #########################################################
  # Auctioning - set starting stock price
  #########################################################

  defevent awaiting_stock_value(player, company, max_price)
           when Constants.is_player(player) and Constants.is_company(company) and
                  is_integer(max_price) do
    [player: player, company: company, max_price: max_price]
  end

  defcommand set_stock_value(auction_winner, company, price)
             when Constants.is_player(auction_winner) and Constants.is_company(company) and
                    is_integer(price) do
    [auction_winner: auction_winner, company: company, price: price]
  end

  defevent stock_value_set(auction_winner, company, value)
           when Constants.is_player(auction_winner) and Constants.is_company(company) and
                  is_integer(value) do
    [auction_winner: auction_winner, company: company, value: value]
  end

  defevent stock_value_rejected(auction_winner, company, price, reason)
           when Constants.is_player(auction_winner) and Constants.is_company(company) and
                  is_binary(reason) do
    [auction_winner: auction_winner, company: company, price: price, reason: reason]
  end

  defevent stock_value_incremented(company) when Constants.is_company(company) do
    [company: company]
  end

  #########################################################
  # Player Turn
  #########################################################

  defcommand(:start_player_turn)

  defevent player_turn_started(player) when Constants.is_player(player) do
    [player: player]
  end

  defevent player_turn_rejected(message) do
    [message: message]
  end

  defevent player_turn_ended(player) when Constants.is_player(player) do
    [player: player]
  end

  #########################################################
  # Player Action Option #1A: Buy Single Stock
  #########################################################

  defcommand purchase_single_stock(purchasing_player, company, price)
             when Constants.is_player(purchasing_player) and Constants.is_company(company) and
                    is_integer(price) do
    [purchasing_player: purchasing_player, company: company, price: price]
  end

  defevent single_stock_purchased(purchasing_player, company, price)
           when Constants.is_player(purchasing_player) and Constants.is_company(company) and
                  is_integer(price) do
    [purchasing_player: purchasing_player, company: company, price: price]
  end

  defevent single_stock_purchase_rejected(purchasing_player, company, price, reason)
           when Constants.is_player(purchasing_player) and Constants.is_company(company) and
                  is_integer(price) and
                  is_binary(reason) do
    [purchasing_player: purchasing_player, company: company, price: price, reason: reason]
  end

  #########################################################
  # Reserving Player Actions
  # Player actions can be complicated, involving input from
  # multiple aggregator. This set of command/events lets us
  # block the current player turn from accepting any new
  # actions until the current one is resolved.
  #########################################################

  defcommand reserve_player_action(player) when Constants.is_player(player) do
    [player: player]
  end

  defevent player_action_rejected(player, reason)
           when Constants.is_player(player) and is_binary(reason) do
    [player: player, reason: reason]
  end

  defevent player_action_reserved(player) when Constants.is_player(player) do
    [player: player]
  end

  #########################################################
  # Player Action Option #2A: Build Rail Link (single)
  #########################################################

  defcommand build_rail_link(player, company, rail_link)
             when Constants.is_player(player) and
                    Constants.is_company(company) and
                    Constants.is_rail_link(rail_link) do
    [player: player, company: company, rail_link: rail_link]
  end

  defevent rail_link_sequence_begun(player, company, rail_link)
           when Constants.is_player(player) and
                  Constants.is_company(company) and
                  Constants.is_rail_link(rail_link) do
    [player: player, company: company, rail_link: rail_link]
  end

  defevent rail_link_built(player, company, rail_link)
           when Constants.is_player(player) and Constants.is_company(company) and
                  Constants.is_rail_link(rail_link) do
    [player: player, company: company, rail_link: rail_link]
  end

  defevent rail_link_rejected(player, company, rail_link, reasons)
           when Constants.is_player(player) and
                  Constants.is_company(company) and
                  Constants.is_rail_link(rail_link) and
                  is_list(reasons) do
    [player: player, company: company, rail_link: rail_link, reasons: reasons]
  end

  # -------------------------------------------------------
  # Company must be public
  # -------------------------------------------------------

  defcommand check_is_company_public(company) when Constants.is_company(company) do
    [company: company]
  end

  defevent company_is_public(company) when Constants.is_company(company) do
    [company: company]
  end

  defevent company_is_not_public(company) when Constants.is_company(company) do
    [company: company]
  end

  #########################################################
  # Player Action Option #3: Pass
  #########################################################

  defcommand pass(passing_player) when Constants.is_player(passing_player) do
    [passing_player: passing_player]
  end

  defevent passed(passing_player) when Constants.is_player(passing_player) do
    [passing_player: passing_player]
  end

  defevent pass_rejected(passing_player, reason)
           when Constants.is_player(passing_player) and is_binary(reason) do
    [passing_player: passing_player, reason: reason]
  end

  #########################################################
  # End of Turn Sequence
  #########################################################

  defcommand(:start_interturn)

  # If the timing track is sufficiently advanced, then:
  simple_event(:interturn_started)
  # otherwise:
  simple_event(:interturn_skipped)

  # If a :interturn_started event has been issued,
  # then when it's finished:
  simple_event(:interturn_ended)

  #########################################################
  # Timing Track
  #########################################################

  simple_event(:timing_track_reset)
  simple_event(:timing_track_incremented)

  #########################################################
  # Dividends
  #########################################################

  # Emitted by Interturn as part of the response to interturn_started.
  defcommand(pay_dividends(), do: [])

  # Emitted and consumed by IncomeTrack
  defevent paying_dividends() do
    []
  end

  # Emitted by IncomeTrack in response to pay_dividends.
  # It will wait for a corresponding company_dividends_paid event before emitting
  # another for the next company.
  defcommand pay_company_dividends(company, income) do
    [company: company, income: income]
  end

  # Emitted by StockCertificates in response to pay_company_dividends.
  # It also emits money_transferred
  defevent company_dividends_paid(
             company,
             company_income,
             stock_count,
             certificate_value,
             command_id
           ) do
    [
      company: company,
      company_income: company_income,
      stock_count: stock_count,
      certificate_value: certificate_value,
      command_id: command_id
    ]
  end

  # Emitted by IncomeTrack after last pay_company_dividends/company_dividends_paid cycle.
  # Consumed by Interturn to trigger the next interturn sequence.
  defevent dividends_paid() do
    []
  end

  #########################################################
  # Nationalization
  #########################################################

  defevent company_nationalized(company) when Constants.is_company(company) do
    [company: company]
  end

  #########################################################
  # Game End Sequence
  #########################################################

  defcommand end_game(causes) when is_list(causes) do
    [causes: causes]
  end

  defevent game_end_sequence_begun(causes) when is_list(causes) do
    [causes: causes]
  end

  defevent game_end_stock_values_determined(companies) when is_list(companies) do
    for company_map <- companies do
      %{company: company, stock_value: stock_value} = company_map

      unless map_size(company_map) == 2 and Constants.is_company(company) and
               is_integer(stock_value) do
        raise ArgumentError,
              "companies argument must be a list of maps with :company and :stock_value keys. Got: #{inspect(companies)}"
      end
    end

    note =
      "this takes nationalization into account but ignores the effect of private companies, " <>
        "the value of whose stock certificates is actually zero at game end"

    [companies: companies, note: note]
  end

  defevent game_end_player_stock_values_calculated(player_stock_values)
           when is_list(player_stock_values) do
    player_stock_values =
      Enum.map(player_stock_values, fn stock_values ->
        types = %{
          player: :integer,
          company: :string,
          count: :integer,
          value_per: :integer,
          total_value: :integer,
          public_cert_count: :integer
        }

        keys = Map.keys(stock_values)

        changeset =
          {%{}, types}
          |> Changeset.cast(stock_values, keys)
          |> Changeset.validate_required(keys)
          |> Changeset.validate_inclusion(:player, 1..5)
          |> Changeset.validate_inclusion(:company, Constants.companies())
          |> Changeset.validate_inclusion(:count, 1..5)
          |> Changeset.validate_number(:value_per, greater_than_or_equal_to: 0)
          |> Changeset.validate_number(:total_value, greater_than_or_equal_to: 0)
          |> Changeset.validate_inclusion(:public_cert_count, 1..5)

        if changeset.valid? do
          Changeset.apply_changes(changeset)
        else
          raise ArgumentError, "Invalid stock_map: #{inspect(changeset.errors)}"
        end
      end)

    [player_stock_values: player_stock_values]
  end

  defevent game_end_player_money_calculated(player_money) do
    types = %{player: :integer, money: :integer}
    keys = Map.keys(types)

    player_money =
      Enum.map(player_money, fn map ->
        changeset =
          {%{}, types}
          |> Changeset.cast(map, keys)
          |> Changeset.validate_required(keys)
          |> Changeset.validate_inclusion(:player, 1..5)
          |> Changeset.validate_number(:money, greater_than_or_equal_to: 0)

        if changeset.valid? do
          Changeset.apply_changes(changeset)
        else
          raise ArgumentError, "Invalid player money: #{inspect(changeset.errors)}"
        end
      end)

    [player_money: player_money]
  end

  defevent player_scores_calculated(player_scores) do
    types = %{player: :integer, score: :integer}
    keys = Map.keys(types)

    player_scores =
      Enum.map(player_scores, fn map ->
        changeset =
          {%{}, types}
          |> Changeset.cast(map, keys)
          |> Changeset.validate_required(keys)
          |> Changeset.validate_inclusion(:player, 1..5)
          |> Changeset.validate_number(:score, greater_than_or_equal_to: 0)

        if changeset.valid? do
          Changeset.apply_changes(changeset)
        else
          raise ArgumentError, "Invalid player score: #{inspect(changeset.errors)}"
        end
      end)

    [player_scores: player_scores]
  end

  defevent winners_determined(winners, score)
           when is_list(winners) and is_integer(score) and score >= 0 do
    for winner <- winners do
      unless Constants.is_player(winner) do
        raise ArgumentError, "winners must be a list of integers, got: #{inspect(winners)}"
      end
    end

    [winners: winners, score: score]
  end

  defevent game_ended(game_id) when is_binary(game_id) do
    [game_id: game_id]
  end
end
