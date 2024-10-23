defmodule TransSiberianRailroad.Aggregator.PlayerTurn do
  @moduledoc """
  TODO
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

    field :fetched_next_player, {:ok, Player.id()} | {:error, String.t()},
      default: {:error, "no start player set"}

    field :player_order, [Player.id()]

    # This is how many the have available to auction/sell
    field :company_stock_counts, %{Company.id() => non_neg_integer()}, default: %{}

    field :player_money_balances, %{(Player.id() | Company.id()) => non_neg_integer()},
      default: %{}

    # If a company is not in this map, it never had its first stock auctioned off
    field :companies, %{Company.id() => :active | :nationalized}, default: %{}

    # TODO rename to ..... state?
    field :next_reaction, :player_turn | :player_turn_started
  end

  handle_event "player_order_set", ctx do
    %{player_order: player_order} = ctx.payload
    [player_order: player_order]
  end

  #########################################################
  # Next Player
  #########################################################

  handle_event "start_player_set", ctx do
    %{start_player: next_player} = ctx.payload
    [fetched_next_player: {:ok, next_player}]
  end

  handle_event "player_won_company_auction", ctx do
    %{auction_winner: next_player, company: company} = ctx.payload
    companies = Map.put(ctx.projection.companies, company, :active)
    # TODO but not if it's phase 2 auction
    [fetched_next_player: {:ok, next_player}, companies: companies]
  end

  #########################################################
  # Money and Stock Balances
  #########################################################

  handle_event "money_transferred", ctx do
    transfers = ctx.payload.transfers
    player_money_balances = ctx.projection.player_money_balances

    new_player_money_balances =
      Enum.reduce(transfers, player_money_balances, fn
        {entity, amount}, balances when Player.is_id(entity) ->
          Map.update(balances, entity, amount, &(&1 + amount))

        _, balances ->
          balances
      end)

    [player_money_balances: new_player_money_balances]
  end

  handle_event "stock_certificates_transferred", ctx do
    %{from: from, to: to, quantity: quantity} = ctx.payload
    transfers = %{from => -quantity, to => quantity}

    company_stock_counts =
      Enum.reduce(transfers, ctx.projection.company_stock_counts, fn {entity, amount},
                                                                     company_stock_counts ->
        if Company.is_id(entity) do
          Map.update(company_stock_counts, entity, amount, &(&1 + amount))
        else
          company_stock_counts
        end
      end)

    [company_stock_counts: company_stock_counts]
  end

  #########################################################
  # Starting and endind the Player Turn
  #########################################################

  handle_event "auction_phase_ended", ctx do
    %{phase_number: phase_number} = ctx.payload

    if phase_number == 1 do
      [next_reaction: :player_turn_started]
    else
      []
    end
  end

  defreaction maybe_start_player_turn(projection) do
    with {:ok, next_player} <- projection.fetched_next_player,
         :player_turn_started <- projection.next_reaction do
      metadata = Projection.next_metadata(projection)
      Messages.player_turn_started(next_player, metadata)
    else
      _ -> nil
    end
  end

  # TODO mv to Current Player section?
  handle_event "player_turn_started", ctx do
    %{player: current_player} = ctx.payload
    fetched_next_player = fetch_next_player(ctx.projection, current_player)

    [
      next_reaction: :player_turn,
      fetched_next_player: fetched_next_player
    ]
  end

  handle_event "end_of_turn_sequence_started", _ctx do
    [next_reaction: nil]
  end

  handle_event "end_of_turn_sequence_ended", _ctx do
    [next_reaction: :player_turn_started]
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
         :ok <- validate_company_stock_count(projection, company) do
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
  # Converters
  #########################################################

  defp validate_player_turn(projection) do
    case projection.next_reaction do
      :player_turn -> :ok
      _ -> {:error, "not a player turn"}
    end
  end

  defp validate_current_player(projection, player) do
    case fetch_current_player(projection) do
      {:ok, ^player} -> :ok
      {:ok, _} -> {:error, "incorrect player"}
      error -> error
    end
  end

  defp validate_active_company(projection, company) do
    case Map.get(projection.companies, company) do
      nil -> {:error, "company was never active"}
      :active -> :ok
      :nationalized -> {:error, "company nationalized"}
    end
  end

  defp validate_funds(projection, player, price) do
    case Map.get(projection.player_money_balances, player) do
      nil -> {:error, "player does not exist"}
      balance when is_integer(balance) and balance >= price -> :ok
      _ -> {:error, "insufficient funds"}
    end
  end

  defp validate_company_stock_count(projection, company) do
    case Map.get(projection.company_stock_counts, company) do
      nil -> {:error, "company seems to have had no stock transfers"}
      count when is_integer(count) and count > 0 -> :ok
      _ -> {:error, "company has no stock to sell"}
    end
  end

  defp fetch_current_player(projection) do
    with {:ok, player_order} <- fetch_player_order(projection),
         {:ok, next_player} <- projection.fetched_next_player do
      current_player = Players.previous_player(player_order, next_player)
      {:ok, current_player}
    end
  end

  defp fetch_player_order(projection) do
    case projection.player_order do
      nil -> {:error, "No player order"}
      player_order when is_list(player_order) -> {:ok, player_order}
    end
  end

  defp fetch_next_player(projection, current_player) do
    with {:ok, player_order} <- fetch_player_order(projection) do
      # TODO rename to indicate that it's a tuple?
      {:ok, Players.next_player(player_order, current_player)}
    end
  end
end
