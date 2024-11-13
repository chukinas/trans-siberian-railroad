defmodule TransSiberianRailroad.Aggregator.PlayerTurn do
  @moduledoc """
  This module handles the player's turn.

  Players may:
  - purchase stock (one or two)
  - pass
  - lay rail for a company they have a majority stake in (one or two rail links)
  """

  use TransSiberianRailroad.Aggregator
  use TransSiberianRailroad.Projection
  require TransSiberianRailroad.Constants, as: Constants
  alias TransSiberianRailroad.Messages
  alias TransSiberianRailroad.Players

  #########################################################
  # PROJECTION
  #########################################################

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
    %{auction_winner: next_player, company: company} = ctx.payload
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

  handle_event "money_transferred", ctx do
    transfers = ctx.payload.transfers
    player_money = ctx.projection.player_money

    new_player_money_balances =
      Enum.reduce(transfers, player_money, fn
        {entity, amount}, balances when Constants.is_player(entity) ->
          Map.update(balances, entity, amount, &(&1 + amount))

        _, balances ->
          balances
      end)

    [player_money: new_player_money_balances]
  end

  #########################################################
  # :companies[company].stock_count
  #########################################################

  handle_event "stock_certificates_transferred", ctx do
    %{from: from, to: to, quantity: quantity} = ctx.payload
    transfers = %{from => -quantity, to => quantity}

    companies =
      Enum.reduce(transfers, ctx.projection.companies, fn {entity, amount}, companies ->
        if Constants.is_company(entity) do
          update_in(companies, [entity, :stock_count], &(&1 + amount))
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
    %{company: company, value: stock_value} = ctx.payload
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
      &Messages.player_turn_started(next_player, &1)
    else
      {:error, msg} -> &Messages.player_turn_rejected(msg, &1)
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
  # Player Action Option #1: Buy Stock
  #########################################################

  handle_command "purchase_single_stock", ctx do
    %{purchasing_player: purchasing_player, company: company, price: price} = ctx.payload
    projection = ctx.projection

    with :ok <- validate_player_turn(projection),
         :ok <- validate_current_player(projection, purchasing_player),
         :ok <- validate_active_company(projection, company),
         :ok <- validate_funds(projection, purchasing_player, price),
         :ok <- validate_company_stock_count(projection, company),
         :ok <- validate_company_stock_value(projection, company, price) do
      transfers = %{purchasing_player => -price, company => price}
      reason = "single stock purchased"

      [
        &Messages.single_stock_purchased(purchasing_player, company, price, &1),
        &Messages.stock_certificates_transferred(
          company,
          company,
          purchasing_player,
          1,
          reason,
          &1
        ),
        &Messages.money_transferred(transfers, reason, &1),
        &Messages.player_turn_ended(purchasing_player, &1)
      ]
    else
      {:error, reason} ->
        Messages.single_stock_purchase_rejected(
          purchasing_player,
          company,
          price,
          reason,
          ctx.metadata.(0)
        )
    end
  end

  #########################################################
  # Player Action Option #3: Pass
  #########################################################

  handle_command "pass", ctx do
    %{passing_player: passing_player} = ctx.payload
    projection = ctx.projection

    with :ok <- validate_player_turn(projection),
         :ok <- validate_current_player(projection, passing_player) do
      [
        &Messages.passed(passing_player, &1),
        &Messages.timing_track_incremented(&1),
        &Messages.player_turn_ended(passing_player, &1)
      ]
    else
      {:error, reason} -> &Messages.pass_rejected(passing_player, reason, &1)
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

  defp validate_company_stock_value(projection, company, price) do
    case projection.companies[company][:stock_value] do
      ^price -> :ok
      _ -> {:error, "does not match current stock price"}
    end
  end

  defp validate_funds(projection, player, price) do
    case Map.get(projection.player_money, player) do
      nil -> {:error, "player does not exist"}
      balance when is_integer(balance) and balance >= price -> :ok
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
