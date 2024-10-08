defmodule TransSiberianRailroad.Aggregator.Companies do
  use TransSiberianRailroad.Aggregator
  # TODO rename to just Company
  alias TransSiberianRailroad.RailCompany

  @type t() :: [RailCompany.t()]

  #########################################################
  # CONSTRUCTORS
  #########################################################

  @impl true
  def init() do
    RailCompany.ids() |> Enum.map(&RailCompany.new/1)
  end

  #########################################################
  # REDUCERS
  #########################################################

  @impl true
  # TODO
  def put_version(companies, _version) do
    companies
  end

  #########################################################
  # REDUCERS (command handlers)
  #########################################################

  # TODO this should prob be a behaviour function
  defp handle_command(_companies, _unhandled_command_name, _unhandled_payload), do: nil

  #########################################################
  # REDUCERS (event handlers)
  #########################################################

  @impl true
  def handle_event(state, "company_auction_started", %{company_id: company_id}) do
    Keyword.replace!(state, company_id, :auctioning)
  end

  def handle_event(state, "company_opened", %{company_id: company_id, bid_amount: bid_amount}) do
    Keyword.update!(state, company_id, &RailCompany.open(&1, bid_amount))
  end

  def handle_event(state, "company_removed_from_game", %{company_id: company_id}) do
    Keyword.replace!(state, company_id, :removed_from_game)
  end

  def handle_event(state, _unhandled_event_name, _unhandled_payload), do: state

  #########################################################
  # CONVERTERS
  #########################################################

  def get_active(state) do
    state
    |> Keyword.values()
    |> Enum.filter(&(&1.state == :active))
  end
end
