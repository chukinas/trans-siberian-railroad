defmodule TransSiberianRailroad.Aggregator.Companies do
  alias TransSiberianRailroad.Event
  # TODO rename to just Company
  alias TransSiberianRailroad.RailCompany

  #########################################################
  # CONSTRUCTORS
  #########################################################

  def init() do
    RailCompany.ids() |> Enum.map(&RailCompany.new/1)
  end

  # TODO is this the right name for this?
  def state(events) do
    Event.sort(events)
    |> Enum.reduce(init(), fn %Event{name: event_name, payload: payload}, state ->
      handle_event(state, event_name, payload)
    end)
  end

  #########################################################
  # REDUCERS
  #########################################################

  defp handle_event(state, "company_auction_started", %{company_id: company_id}) do
    Keyword.replace!(state, company_id, :auctioning)
  end

  defp handle_event(state, "company_opened", %{company_id: company_id, bid_amount: bid_amount}) do
    Keyword.update!(state, company_id, &RailCompany.open(&1, bid_amount))
  end

  defp handle_event(state, "company_removed_from_game", %{company_id: company_id}) do
    Keyword.replace!(state, company_id, :removed_from_game)
  end

  defp handle_event(state, _unhandled_event_name, _unhandled_payload), do: state

  #########################################################
  # CONVERTERS
  #########################################################

  def get_active(state) do
    state
    |> Keyword.values()
    |> Enum.filter(&(&1.state == :active))
  end
end
