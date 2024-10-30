defmodule TransSiberianRailroad.Company do
  @moduledoc """
  A rail company sells shares to players;
  this is its main source of income.
  A player with a controlling interest in a public company
  can have that company build track, which is paid for by the company.
  Building track increases a company's income,
  which increases the dividends payout to stockholders.

  This module will be heavily modified in the future, or removed entirely.
  This is because since its originally creation, all the event generation is now
  based entirely on internal aggregator state.
  """

  use TypedStruct

  @phase_1_ids ~w(red blue green yellow)a
  @phase_2_ids ~w(black white)a
  @all_ids @phase_1_ids ++ @phase_2_ids
  @type id() :: :red | :blue | :green | :yellow | :black | :white

  # An :active company is either private or public (calculated).
  @type state() :: :unauctioned | :waiting | :up_for_auction | :rejected | :active | :nationalized

  typedstruct enforce: true do
    field :id, id()
    field :state, state()
    field :money, non_neg_integer()
    field :share_count, non_neg_integer()
  end

  #########################################################
  # CONSTRUCTORS
  #########################################################

  def new(id) do
    %__MODULE__{
      id: id,
      state: :unauctioned,
      money: 0,
      share_count: initial_share_count(id)
    }
  end

  #########################################################
  # REDUCERS
  #########################################################

  def open(%__MODULE__{state: :unauctioned, money: 0} = company, bid_amount) do
    %__MODULE__{company | state: :active, money: bid_amount}
    |> sell_share()
  end

  def sell_share(%__MODULE__{share_count: share_count} = company) when share_count >= 1 do
    %__MODULE__{company | share_count: share_count - 1}
  end

  #########################################################
  # CONVERTERS (guards)
  #########################################################

  defguard is_id(id) when id in @all_ids

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

  def ids(), do: @all_ids

  def ids(phase_number)
  def ids(1), do: @phase_1_ids
  def ids(2), do: @phase_2_ids

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
