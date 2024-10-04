defmodule TransSiberianRailroad.Statechart do
  @moduledoc """
  The game goes through several well-defined phases.
  First, we set up (collect players, etc.).
  Then we play the game.
  Finally, we end the game (calculate scores, etc.)

  ## Notes
  - Move some of these to a PlayerTurn module?
    This would have the "current player id"
  """

  alias TransSiberianRailroad.Player
  alias TransSiberianRailroad.RailCompany

  @typep auction() :: %{
           current_company_id: RailCompany.id(),
           remaining_companies_in_this_auction: [RailCompany.id()],
           current_bidder: Player.id()
         }

  @typep in_progress_state() :: %{
           current_player_turn: Player.id(),
           auction: nil | auction()
         }

  @opaque t() :: :setup | {:in_progress, in_progress_state()} | :ended

  #########################################################
  # CONSTRUCTORS
  #########################################################

  def new(), do: :setup

  #########################################################
  # REDUCERS
  #########################################################

  def start_game(:setup, first_player) when first_player in 1..5 do
    {:in_progress, %{current_player_turn: first_player}}
  end

  def end_game({:in_progress, _}), do: :ended

  #########################################################
  # CONVERTERS
  #########################################################

  def ended?(:ended), do: true
  def ended?(_), do: false
end
