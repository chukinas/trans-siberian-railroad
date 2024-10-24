defmodule TransSiberianRailroad.Aggregator.PlayerTurn do
  @moduledoc """
  This module handles the player's turn.

  Players may:
  - purchase stock
  - pass
  - lay rail for a company they have a majority stake in
  """

  use TransSiberianRailroad.Aggregator
  use TransSiberianRailroad.Projection
  require TransSiberianRailroad.Player, as: Player
  require TransSiberianRailroad.RailCompany, as: Company
  alias TransSiberianRailroad.Messages
  alias TransSiberianRailroad.Players

  #########################################################
  # PROJECTION
  #########################################################

  typedstruct opaque: true do
    projection_fields()

    field :player_order, [Player.id()]

    field :fetched_next_player, {:ok, Player.id()} | {:error, String.t()},
      default: {:error, "no start player set"}

    field :player_money, %{(Player.id() | Company.id()) => non_neg_integer()}, default: %{}

    field :companies, %{Company.id() => map()},
      default:
        Map.new(
          Company.ids(),
          &{&1, %{stock_count: 0, stock_price: nil, state: :unauctioned}}
        )

    # If :not_started, no one's had a first turn yet. We're setting up or doing the first auction phase.
    # If :in_progress, we are in the middle of a player's turn, awaiting their command.
    # If :start_player_turn, we are ready to start the next player's turn.
    # If :end_of_turn, we are in the middle of the end-of-turn sequence.
    field :readiness, :not_started | :in_progress | :start_player_turn | :end_of_turn,
      default: :not_started
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

  handle_event "player_won_company_auction", ctx do
    %{auction_winner: next_player, company: company} = ctx.payload
    companies = ctx.projection.companies |> put_in([company, :state], :active)
    fields = [companies: companies]

    if ctx.projection.readiness == :not_started do
      Keyword.put(fields, :fetched_next_player, {:ok, next_player})
    else
      fields
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
        {entity, amount}, balances when Player.is_id(entity) ->
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
        if Company.is_id(entity) do
          update_in(companies, [entity, :stock_count], &(&1 + amount))
        else
          companies
        end
      end)

    [companies: companies]
  end

  #########################################################
  # :companies[company].stock_price
  #########################################################

  handle_event("starting_stock_price_set", ctx, do: stock_price(ctx))
  handle_event("stock_price_increased", ctx, do: stock_price(ctx))

  defp stock_price(ctx) do
    %{company: company, price: stock_price} = ctx.payload
    companies = ctx.projection.companies |> put_in([company, :stock_price], stock_price)
    [companies: companies]
  end

  #########################################################
  # Starting and endind the Player Turn
  #########################################################

  handle_event "auction_phase_ended", ctx do
    %{phase_number: phase_number} = ctx.payload

    if phase_number == 1 do
      [readiness: :start_player_turn]
    end
  end

  defreaction maybe_start_player_turn(projection) do
    with {:ok, next_player} <- projection.fetched_next_player,
         :start_player_turn <- projection.readiness do
      metadata = Projection.next_metadata(projection)
      Messages.player_turn_started(next_player, metadata)
    else
      _ -> nil
    end
  end

  handle_event "player_turn_started", ctx do
    %{player: current_player} = ctx.payload
    fetched_next_player = fetch_next_player(ctx.projection, current_player)
    [readiness: :in_progress, fetched_next_player: fetched_next_player]
  end

  handle_event "end_of_turn_sequence_started", _ctx do
    [readiness: :end_of_turn]
  end

  handle_event "end_of_turn_sequence_ended", _ctx do
    [readiness: :start_player_turn]
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
         :ok <- validate_company_stock_price(projection, company, price) do
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
        &Messages.end_of_turn_sequence_started(&1)
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
        &Messages.end_of_turn_sequence_started(&1)
      ]
    else
      {:error, reason} -> &Messages.pass_rejected(passing_player, reason, &1)
    end
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

  defp validate_company_stock_price(projection, company, price) do
    case projection.companies[company][:stock_price] do
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

  defp validate_player_turn(projection) do
    case projection.readiness do
      :in_progress -> :ok
      _ -> {:error, "not a player turn"}
    end
  end
end
