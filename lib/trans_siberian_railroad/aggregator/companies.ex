defmodule TransSiberianRailroad.Aggregator.Companies do
  use TransSiberianRailroad.Aggregator
  # TODO rename to just Company
  alias TransSiberianRailroad.RailCompany

  @type t() :: %{RailCompany.id() => RailCompany.t()}

  #########################################################
  # CONSTRUCTORS
  #########################################################

  @impl true
  def init() do
    RailCompany.ids()
    |> Map.new(fn company_id -> {company_id, RailCompany.new(company_id)} end)
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
  # CONVERTERS
  #########################################################

  def get_active(state) do
    state
    |> Keyword.values()
    |> Enum.filter(&(&1.state == :active))
  end
end
