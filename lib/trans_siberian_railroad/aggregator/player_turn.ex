defmodule TransSiberianRailroad.Aggregator.PlayerTurn do
  @moduledoc """
  This module handles the player's turn.

  Players may:
  - purchase stock (one or two)
  - pass
  - lay rail for a company they have a majority stake in (one or two rail links)
  """

  use TransSiberianRailroad.Aggregator
  alias TransSiberianRailroad.Players

  aggregator_typedstruct do
    field :player_order, [Constants.player()]

    field :fetched_next_player, {:ok, Constants.player()} | {:error, String.t()},
      default: {:error, "no start player set"}

    # If nil, then no player turn is in progress.
    # If a player ID, then that player is taking their turn.
    field :current_player, Constants.player()

    field :player_money, %{(Constants.player() | Constants.company()) => non_neg_integer()},
      default: %{}

    field :companies, %{Constants.company() => map()},
      default:
        Map.new(
          Constants.companies(),
          &{&1, %{stock_count: 0, stock_value: nil, state: :unauctioned}}
        )
  end

  handle_command "start_auction_phase", ctx do
    %{phase: phase} = ctx.payload
    {:ok, next_player} = ctx.projection.fetched_next_player
    player_order = ctx.projection.player_order

    start_player =
      case phase do
        1 -> next_player
        2 -> TransSiberianRailroad.Players.previous_player(player_order, next_player)
      end

    event_builder("auction_phase_started", phase: phase, start_player: start_player)
  end

  #########################################################
  # :player_order
  #########################################################

  handle_event "player_order_set", ctx do
    %{player_order: player_order} = ctx.payload
    [player_order: player_order]
  end

  #########################################################
  # :fetched_next_player
  #########################################################

  handle_event "start_player_set", ctx do
    %{start_player: next_player} = ctx.payload
    [fetched_next_player: {:ok, next_player}]
  end

  @phase_1_companies Constants.companies() |> Enum.take(4)
  handle_event "player_won_company_auction", ctx do
    %{player: next_player, company: company} = ctx.payload
    companies = put_in(ctx.projection.companies, [company, :state], :active)

    if company in @phase_1_companies do
      [companies: companies, fetched_next_player: {:ok, next_player}]
    else
      [companies: companies]
    end
  end

  #########################################################
  # :player_money
  #########################################################

  handle_event "rubles_transferred", ctx do
    transfers = ctx.payload.transfers
    player_money = ctx.projection.player_money

    new_player_money_balances =
      Enum.reduce(transfers, player_money, fn
        %{entity: entity, rubles: rubles}, balances when Constants.is_player(entity) ->
          Map.update(balances, entity, rubles, &(&1 + rubles))

        _, balances ->
          balances
      end)

    [player_money: new_player_money_balances]
  end

  #########################################################
  # :companies[company].stock_count
  #########################################################

  handle_event "stock_certificates_transferred", ctx do
    %{from: from, to: to, count: count} = ctx.payload
    transfers = %{from => -count, to => count}

    companies =
      Enum.reduce(transfers, ctx.projection.companies, fn {entity, count}, companies ->
        if Constants.is_company(entity) do
          update_in(companies, [entity, :stock_count], &(&1 + count))
        else
          companies
        end
      end)

    [companies: companies]
  end

  #########################################################
  # :companies[company].stock_value
  #########################################################

  handle_event "stock_value_set", ctx do
    %{company: company, stock_value: stock_value} = ctx.payload
    companies = ctx.projection.companies |> put_in([company, :stock_value], stock_value)
    [companies: companies]
  end

  #########################################################
  # Starting and ending the Player Turn
  #########################################################

  handle_command "start_player_turn", ctx do
    projection = ctx.projection

    with {:ok, next_player} <- projection.fetched_next_player,
         :ok <- validate_not_player_turn(projection) do
      event_builder("player_turn_started", player: next_player)
    else
      {:error, msg} -> event_builder("player_turn_rejected", reason: msg)
    end
  end

  handle_event "player_turn_started", ctx do
    %{player: current_player} = ctx.payload
    fetched_next_player = fetch_next_player(ctx.projection, current_player)

    [
      fetched_next_player: fetched_next_player,
      current_player: current_player
    ]
  end

  #########################################################
  # Checking Player Turn
  #########################################################

  handle_command "reserve_player_action", ctx do
    %{player: player} = ctx.payload
    projection = ctx.projection

    with :ok <- validate_player_turn(projection),
         :ok <- validate_current_player(projection, player) do
      Messages.event_builder("player_action_reserved", player: player)
    else
      {:error, reason} ->
        Messages.event_builder("player_action_rejected", player: player, reason: reason)
    end
  end

  #########################################################
  # Player Action Option #1: Buy Stock
  #########################################################

  handle_command "purchase_single_stock", ctx do
    %{player: purchasing_player, company: company, rubles: rubles} = ctx.payload
    projection = ctx.projection

    with :ok <- validate_player_turn(projection),
         :ok <- validate_current_player(projection, purchasing_player),
         :ok <- validate_active_company(projection, company),
         :ok <- validate_funds(projection, purchasing_player, rubles),
         :ok <- validate_company_stock_count(projection, company),
         :ok <- validate_company_stock_value(projection, company, rubles) do
      reason = "single stock purchased"

      [
        event_builder("single_stock_purchased",
          player: purchasing_player,
          company: company,
          rubles: rubles
        ),
        event_builder("stock_certificates_transferred",
          company: company,
          from: company,
          to: purchasing_player,
          count: 1,
          reason: reason
        )
      ]
    else
      {:error, reason} ->
        event_builder("single_stock_purchase_rejected",
          player: purchasing_player,
          company: company,
          rubles: rubles,
          reason: reason
        )
    end
  end

  #########################################################
  # Player Action Option #3: Pass
  #########################################################

  handle_command "pass", ctx do
    %{player: passing_player} = ctx.payload
    projection = ctx.projection

    with :ok <- validate_player_turn(projection),
         :ok <- validate_current_player(projection, passing_player) do
      event_builder("passed", player: passing_player)
    else
      {:error, reason} -> event_builder("pass_rejected", player: passing_player, reason: reason)
    end
  end

  #########################################################
  # End Turn
  #########################################################

  handle_event "player_turn_ended", _ctx do
    [current_player: nil]
  end

  #########################################################
  # Fetchers
  # return {:ok, value} on success, {:error, reason} on failure
  #########################################################

  defp fetch_current_player(projection) do
    with {:ok, player_order} <- fetch_player_order(projection),
         {:ok, next_player} <- projection.fetched_next_player do
      current_player = Players.previous_player(player_order, next_player)
      {:ok, current_player}
    end
  end

  defp fetch_next_player(projection, current_player) do
    with {:ok, player_order} <- fetch_player_order(projection) do
      {:ok, Players.next_player(player_order, current_player)}
    end
  end

  defp fetch_player_order(projection) do
    case projection.player_order do
      nil -> {:error, "No player order"}
      player_order when is_list(player_order) -> {:ok, player_order}
    end
  end

  #########################################################
  # Validators
  # return :ok on success, {:error, reason} on failure
  #########################################################

  defp validate_active_company(projection, company) do
    case projection.companies[company][:state] do
      :unauctioned -> {:error, "company was never active"}
      :active -> :ok
      :nationalized -> {:error, "company nationalized"}
      _ -> {:error, "other"}
    end
  end

  defp validate_current_player(projection, player) do
    case fetch_current_player(projection) do
      {:ok, ^player} -> :ok
      {:ok, _} -> {:error, "incorrect player"}
      error -> error
    end
  end

  defp validate_company_stock_count(projection, company) do
    case projection.companies[company][:stock_count] do
      count when is_integer(count) and count > 0 -> :ok
      0 -> {:error, "company has no stock to sell"}
      _ -> {:error, "other"}
    end
  end

  defp validate_company_stock_value(projection, company, stock_value) do
    case projection.companies[company][:stock_value] do
      ^stock_value -> :ok
      _ -> {:error, "does not match current stock value"}
    end
  end

  defp validate_funds(projection, player, rubles) do
    case Map.get(projection.player_money, player) do
      nil -> {:error, "player does not exist"}
      balance when is_integer(balance) and balance >= rubles -> :ok
      _ -> {:error, "insufficient funds"}
    end
  end

  defp validate_not_player_turn(projection) do
    case validate_player_turn(projection) do
      :ok -> {:error, "A player's turn is already in progress"}
      {:error, _} -> :ok
    end
  end

  defp validate_player_turn(projection) do
    if projection.current_player do
      :ok
    else
      {:error, "not a player turn"}
    end
  end
end
