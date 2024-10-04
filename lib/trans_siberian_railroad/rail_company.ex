defmodule TransSiberianRailroad.RailCompany do
  @moduledoc """
  A rail company sells shares to players;
  this is its main source of income.
  A player with a controlling interest in a public company
  can have that company build track, which is paid for by the company.
  Building track increases a company's income,
  which increases the dividends payout to stockholders.
  """

  use TypedStruct

  @phase_1_ids ~w(red blue green yellow)a
  @phase_2_ids ~w(black white)a
  @all_ids @phase_1_ids ++ @phase_2_ids
  @type id() :: :red | :blue | :green | :yellow | :black | :white

  @type state() :: :waiting | :up_for_auction

  typedstruct enforce: true do
    field :id, id()
    field :state, state()
    field :money, non_neg_integer()
    field :share_count, non_neg_integer()
  end

  #########################################################
  # CONVERTERS (games states)
  #########################################################

  def private?(%__MODULE__{} = company) do
    shares_sold(company) == 1 and not nationalized?(company)
  end

  def public?(%__MODULE__{} = company) do
    shares_sold(company) >= 2 and not nationalized?(company)
  end

  def nationalized?(%__MODULE__{}) do
    # TODO
    false
  end

  defp shares_sold(%__MODULE__{id: id, share_count: share_count}) do
    initial_share_count(id) - share_count
  end

  #########################################################
  # HELPERS
  #########################################################

  def phase_1_ids(), do: @phase_1_ids
  def phase_2_ids(), do: @phase_2_ids

  defp initial_share_count(id) when id in @phase_1_ids, do: 5
  defp initial_share_count(id) when id in @phase_2_ids, do: 3

  # defp name(:red), do: "Красный"
  # defp name(:blue), do: "Синий"
  # defp name(:green), do: "Зелёный"
  # defp name(:yellow), do: "Жёлтый"
  # defp name(:black), do: "Чёрный"
  # defp name(:white), do: "Белый"

  #########################################################
  # ALL
  #########################################################

  @type all() :: [t()]

  @spec new_all() :: all()
  def new_all() do
    for id <- @all_ids do
      %__MODULE__{
        id: id,
        state:
          if id in @phase_1_ids do
            :up_for_auction
          else
            :waiting
          end,
        money: 0,
        share_count: initial_share_count(id)
      }
    end
  end
end
