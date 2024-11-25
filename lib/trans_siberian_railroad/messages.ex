defmodule Tsr.Messages do
  @moduledoc """
  This module contains **all** the constructors for `Tsr.Command`
  and `Tsr.Event`.

  The messages described in this file **completely** describe the game's player actions and events (found in rulebook.pdf).

  ## Naming Conventions

  - Commands start with an imperative verb, e.g. `add_player`.
  - Events end with the corresponding past-tense verb, e.g. `player_added`.
  - `..._sequence_started` - an event that kicks off a series of commands and events.
    Usually needed where several domains need to coordinate.
    Typically resolved with a `..._ended` event.
    Sometimes preceeded by a `start_...` command.
    Example: `pay_dividends` -> `dividends_sequence_started` -> `...` -> `dividends_paid`

  ## Notes

  - Sometimes, there are command-event pairs that seem unnecessary, where it seems that only the event is needed.
    But the reason here to still include the command is to make that command available during testing.
    Example: the `end_game` command is used often in the test suite to force a game-end sequence in order to check player's rubles balance.
  """

  use Tsr.Command
  use Tsr.Event
  require Tsr.Constants, as: Constants

  #########################################################
  # "Broad Events"
  # Unlike all the other events, these two events may
  # be issued by **any** aggregator.
  #########################################################

  @type entity() :: Constants.player() | Constants.company() | :bank

  defevent("stock_certificates_transferred", [:company, :from, :to, :count, :reason])

  ##########################################################
  # Rubles
  #########################################################

  defevent("rubles_transferred", [:reason, transfers: [:entity, :rubles]])

  ##########################################################
  # Initializing Game
  #########################################################

  defcommand("initialize_game", [:game_id])
  defevent("game_initialized", [:game_id])
  defevent("game_initialization_rejected", [:game_id, :reason])

  #########################################################
  # Adding Players
  #########################################################

  defcommand("add_player", [:player_name])
  defevent("player_added", [:player, :player_name])
  defevent("player_rejected", [:player_name, :reason])

  #########################################################
  # SETUP - player order and starting player
  #########################################################

  defcommand("set_start_player", [:player])
  defevent("start_player_set", [:start_player])
  defcommand("set_player_order", [:player_order])
  defevent("player_order_set", [:player_order])

  #########################################################
  # Starting Game
  #########################################################

  defcommand("start_game")
  defevent("game_started", [:players])
  defevent("game_start_rejected", [:reason])

  #########################################################
  # Auctioning - open and close an auction phase
  #########################################################

  defcommand("start_auction_phase", [:phase])
  defevent("auction_phase_started", [:phase, :start_player])
  defevent("auction_phase_ended", [:phase, :start_player])

  #########################################################
  # Auctioning - open and close a company auction
  #########################################################

  @doc """
  Begin the bidding for the first share of a company.

  This can result in either "player_won_company_auction" (a player won the share)
  or "all_players_passed_on_company" (no player bid on the share).
  """
  defevent("company_auction_started", [:start_player, :company])

  # This and "player_won_company_auction" both end the company auction started by "company_auction_started".
  defevent("all_players_passed_on_company", [:company])

  # This and "all_players_passed_on_company" both end the company auction started by "company_auction_started".
  # At this point, the company is "Open".
  defevent("player_won_company_auction", [:player, :company, :rubles])
  defevent("company_auction_ended", [:company])

  #########################################################
  # Auctioning - awaiting next player to bid or pass
  #########################################################

  defevent("awaiting_bid_or_pass", [:player, :company, :min_bid])

  #########################################################
  # Auctioning - players pass on a company
  #########################################################

  defcommand("pass_on_company", [:player, :company])
  defevent("company_passed", [:player, :company])
  defevent("company_pass_rejected", [:player, :company, :reason])

  #########################################################
  # Auctioning - players bid on a company
  #########################################################

  defcommand("submit_bid", [:player, :company, :rubles])
  defevent("bid_submitted", [:player, :company, :rubles])
  defevent("bid_rejected", [:player, :company, :rubles, :reason])

  #########################################################
  # Auctioning - initial rail link
  #########################################################

  defevent("awaiting_initial_rail_link", [:player, :company, :available_links])
  defcommand("build_initial_rail_link", [:player, :company, :rail_link])
  defevent("initial_rail_link_rejected", [:player, :company, :rail_link, :reason])
  defevent("initial_rail_link_built", [:player, :company, :rail_link, :link_income])

  #########################################################
  # Auctioning - set starting stock value
  #########################################################

  defevent("awaiting_stock_value", [:player, :company, :max_stock_value])
  defcommand("set_stock_value", [:player, :company, :stock_value])
  defevent("stock_value_set", [:player, :company, :stock_value])
  defevent("stock_value_rejected", [:player, :company, :stock_value, :reason])
  defevent("stock_value_incremented", [:company])

  #########################################################
  # Player Turn
  #########################################################

  defcommand("start_player_turn")
  defevent("player_turn_started", [:player])
  defevent("player_turn_rejected", [:reason])
  defevent("player_turn_ended", [:player])

  #########################################################
  # Player Action Option #1A: Buy Single Stock
  #########################################################

  defcommand("purchase_single_stock", [:player, :company, :rubles])
  defevent("single_stock_purchased", [:player, :company, :rubles])
  defevent("single_stock_purchase_rejected", [:player, :company, :rubles, :reason])

  #########################################################
  # Player Action Option #1A: Buy Two Stock Certificates
  #########################################################

  defevent("two_stock_certificates_purchased", [:player])

  #########################################################
  # Reserving Player Actions
  # Player actions can be complicated, involving input from
  # multiple aggregator. This set of command/events lets us
  # block the current player turn from accepting any new
  # actions until the current one is resolved.
  #########################################################

  defcommand("reserve_player_action", [:player])
  defevent("player_action_reserved", [:player])
  defevent("player_action_rejected", [:player, :reason])

  #########################################################
  # Player Action Option #2A: Build Rail Link (single)
  #########################################################

  @keys [:player, :company, :rail_link]
  @rejection_keys [:reasons | @keys]

  defcommand("build_internal_rail_link", @keys)
  defevent("internal_rail_link_sequence_started", @keys)
  defevent("internal_rail_link_built", @keys)
  defevent("internal_rail_link_rejected", @rejection_keys)

  defcommand("build_external_rail_link", @keys)
  defevent("external_rail_link_sequence_started", @keys)
  defevent("external_rail_link_built", @keys)
  defevent("external_rail_link_rejected", @rejection_keys)

  # Company must be public
  defcommand("validate_public_company", [:company])
  defevent("public_company_validated", [:company, :maybe_error])

  # Player must have controlling share
  defcommand("validate_controlling_share", [:player, :company])
  defevent("controlling_share_validated", [:player, :company, :maybe_error])

  # Rail link must
  defcommand("validate_company_rail_link", [:company, :rail_link])
  defevent("company_rail_link_validated", [:company, :rail_link, :maybe_error])

  # Company must have the rubles
  defcommand("validate_company_money", [:company, :rubles])
  defevent("company_money_validated", [:company, :rubles, :maybe_error])

  #########################################################
  # Player Action Option #2B: Build two Rail Link
  #########################################################

  defevent("two_internal_rail_links_built", [:player])

  #########################################################
  # Player Action Option #3: Pass
  #########################################################

  defcommand("pass", [:player])
  defevent("passed", [:player])
  defevent("pass_rejected", [:player, :reason])

  #########################################################
  # End of Turn Sequence
  #########################################################

  defcommand("start_interturn")
  defevent("interturn_started")
  defevent("interturn_skipped")
  defevent("interturn_ended")

  #########################################################
  # Dividends
  #########################################################

  defcommand("pay_dividends")
  defevent("dividends_sequence_started")
  defcommand("pay_company_dividends", [:company, :income])

  defevent(
    "company_dividends_paid",
    [
      :company,
      :income,
      :stock_count,
      :certificate_value,
      :command_id,
      player_payouts: [:player, :rubles]
    ]
  )

  defevent("dividends_paid")

  #########################################################
  # Phase Shift Check
  #########################################################

  defcommand("check_phase_shift")
  defevent("phase_1_continues")
  defevent("phase_2_started")

  #########################################################
  # Nationalization
  #########################################################

  defevent("company_nationalized", [:company])

  #########################################################
  # Timing Track
  #########################################################

  defevent("timing_track_reset")

  #########################################################
  # Game End Sequence
  #########################################################

  defcommand("end_game", [:reasons])
  defevent("game_end_sequence_started", [:reasons])
  defevent("game_end_stock_values_determined", [:company_stock_values, :note])

  defevent("game_end_player_stock_values_calculated",
    player_stock_values: [
      :player,
      :company,
      :count,
      :value_per,
      :total_value,
      :public_cert_count
    ]
  )

  defevent("game_end_player_money_calculated", player_money: [:player, :rubles])
  defevent("player_scores_calculated", player_scores: [:player, :score])
  defevent("winners_determined", [:players, :score])
  defevent("game_ended", [:game_id])
end
