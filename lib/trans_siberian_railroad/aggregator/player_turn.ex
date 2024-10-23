defmodule TransSiberianRailroad.Aggregator.PlayerTurn do
  @moduledoc """
  TODO
  """

  use TransSiberianRailroad.Aggregator
  use TransSiberianRailroad.Projection
  require TransSiberianRailroad.Player, as: Player
  alias TransSiberianRailroad.RailCompany, as: Company
  alias TransSiberianRailroad.Messages

  #########################################################
  # PROJECTION
  #########################################################

  typedstruct opaque: true do
    version_field()

    field :player_money_balances, %{(Player.id() | Company.id()) => non_neg_integer()},
      default: %{}

    # If a company is not in this map, it never had its first stock auctioned off
    field :companies, %{Company.id() => :active | :nationalized}, default: %{}

    @start_player ~w/awaiting_end_of_first_auction_phase start_player/a
    field :state_machine, [{:atom, Keyword.t()}],
      default: [awaiting_end_of_first_auction_phase: [start_player: nil]]
  end

  #########################################################
  # Listening for Start Player
  #########################################################

  handle_event "start_player_set", ctx do
    %{start_player: start_player} = ctx.payload
    state_machine = put_in(ctx.projection.state_machine, @start_player, start_player)
    [state_machine: state_machine]
  end

  handle_event "player_won_company_auction", ctx do
    %{auction_winner: auction_winner, company: company} = ctx.payload
    companies = Map.put(ctx.projection.companies, company, :active)
    state_machine = put_in(ctx.projection.state_machine, @start_player, auction_winner)
    [companies: companies, state_machine: state_machine]
  end

  #########################################################
  # Money
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

  #########################################################
  # Player Turn Phase 1
  #########################################################

  handle_event "auction_phase_ended", ctx do
    state_machine = [{:first_auction_ended, true} | ctx.projection.state_machine]
    [state_machine: state_machine]
  end

  defreaction maybe_start_player_turn(projection) do
    state_machine = projection.state_machine
    current_player = get_current_player(projection)

    case state_machine do
      [{:first_auction_ended, _} | _] ->
        metadata = Projection.next_metadata(projection)
        Messages.player_turn_started(current_player, metadata)

      _ ->
        nil
    end
  end

  handle_event "player_turn_started", ctx do
    %{player: player} = ctx.payload
    state_machine = put_in(ctx.projection.state_machine, @start_player, player)
    state_machine = [{:player_turn, true} | state_machine]
    [state_machine: state_machine]
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
         :ok <- validate_funds(projection, purchasing_player, price) do
      transfers = %{purchasing_player => -price, company => price}
      reason = "single stock purchased"

      [
        Messages.single_stock_purchased(purchasing_player, company, price, ctx.metadata.(0)),
        Messages.money_transferred(transfers, reason, ctx.metadata.(1)),
        Messages.end_of_turn_sequence_started(ctx.metadata.(2))
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
        Messages.passed(passing_player, ctx.metadata.(0)),
        Messages.end_of_turn_sequence_started(ctx.metadata.(1))
      ]
    else
      {:error, reason} -> Messages.pass_rejected(passing_player, reason, ctx.metadata.(0))
    end
  end

  #########################################################
  # Converters
  #########################################################

  defp validate_player_turn(projection) do
    case Keyword.fetch(projection.state_machine, :player_turn) do
      {:ok, _} -> :ok
      :error -> {:error, "not a player turn"}
    end
  end

  defp validate_current_player(projection, player) do
    case get_current_player(projection) do
      ^player -> :ok
      _ -> {:error, "incorrect player"}
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

  defp get_current_player(projection) do
    get_in(projection.state_machine, @start_player)
  end
end
