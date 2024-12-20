defmodule Tsr.GameTestHelpers do
  import Tsr.CommandFactory
  import Tsr.GameHelpers
  alias Tsr.Event
  alias Tsr.Players

  @stock_value_spaces [8..48//4, 50..70//2, [75]]
                      |> Enum.map(&Enum.to_list/1)
                      |> List.flatten()

  #########################################################
  # Setups
  #########################################################

  defmacro taggable_setups() do
    quote do
      setup context do
        if context[:start_game],
          do: start_game(context),
          else: :ok
      end

      setup context do
        if context[:auction_off_company],
          do: auction_off_company(context),
          else: :ok
      end

      setup context do
        if context[:random_first_auction_phase],
          do: random_first_auction_phase(context),
          else: :ok
      end
    end
  end

  # TODO DRY?
  def start_game(context) do
    {player_count, start_player, player_order} =
      if context[:simple_setup] do
        {3, 1, Enum.to_list(1..3)}
      else
        player_count = context[:player_count] || Enum.random(3..5)
        start_player = context[:start_player] || Enum.random(1..player_count)
        player_order = Enum.to_list(context[:player_order] || Enum.shuffle(1..player_count))
        {player_count, start_player, player_order}
      end

    one_round = Players.one_round(player_order, start_player)

    game =
      handle_commands([
        initialize_game(),
        add_player_commands(player_count),
        set_start_player(start_player),
        set_player_order(player_order),
        start_game()
      ])

    {:ok,
     game: game,
     start_player: start_player,
     player_count: player_count,
     player_order: player_order,
     one_round: one_round}
  end

  # Requires start_game to be run first.
  def auction_off_company(context) do
    # capture state before applying the bids and passing
    game_prior_to_bidding = context.game
    auction_winner = context[:auction_winner] || Enum.random(context.one_round)
    rubles = context[:winning_bid_amount] || 8

    game =
      handle_commands(
        context.game,
        for player <- context.one_round do
          if player == auction_winner do
            submit_bid(player, "red", rubles)
          else
            pass_on_company(player, "red")
          end
        end
      )

    {:ok,
     game_prior_to_bidding: game_prior_to_bidding,
     auction_winner: auction_winner,
     rubles: rubles,
     game: game}
  end

  #########################################################
  # Random Auction Phase 1
  #########################################################

  def random_first_auction_phase(context) do
    game = do_rand_auction_phase(context.game, Map.get(context, :rig_auctions, []))
    start_player = get_one_event(game, "auction_phase_ended").payload.start_player
    [game: game, start_player: start_player]
  end

  defp do_rand_auction_phase(game, rigged_auctions) do
    version_access = [Access.key!(:__test__), Access.key(:version, 0)]
    version = get_in(game, version_access)

    maybe_event =
      game.events
      |> Enum.reverse()
      |> Enum.find(&(Event.await?(&1) and Event.version_gt?(&1, version)))

    version =
      case maybe_event do
        nil -> version
        event -> event.version
      end

    game = put_in(game, version_access, version)

    if event = maybe_event do
      payload = event.payload

      case event.name do
        "awaiting_bid_or_pass" ->
          game
          |> do_bid_or_pass(payload, rigged_auctions)
          |> do_rand_auction_phase(rigged_auctions)

        "awaiting_stock_value" ->
          game
          |> do_stock_value(payload, rigged_auctions)
          |> do_rand_auction_phase(rigged_auctions)

        "awaiting_initial_rail_link" ->
          game |> do_rail_link(payload, rigged_auctions) |> do_rand_auction_phase(rigged_auctions)

        event_name ->
          require Logger
          Logger.warning("event_name: #{event_name} not handled in do_rand_auction_phase/1.")
          do_rand_auction_phase(game, rigged_auctions)
      end
    else
      game
    end
  end

  defp do_bid_or_pass(game, payload, rigged_auctions) do
    %{player: player, company: company, min_bid: min_bid} = payload
    player_money = current_money(game, player)

    maybe_rigged_company_bid = Enum.find(rigged_auctions, &(&1[:company] == company))

    pass? =
      cond do
        player_money < min_bid -> true
        maybe_rigged_company_bid -> maybe_rigged_company_bid[:player] != player
        true -> Enum.random([true, true, false])
      end

    command =
      if pass? do
        pass_on_company(player, company)
      else
        rigged_bid =
          case Enum.find(rigged_auctions, &(&1[:company] == company)) do
            %{rubles: rubles} -> rubles
            _ -> nil
          end

        bid = rigged_bid || Enum.to_list(min_bid..player_money) |> Enum.random()
        submit_bid(player, company, bid)
      end

    handle_commands(game, [command])
  end

  defp do_stock_value(game, payload, rigged_auctions) do
    %{player: player, company: company, max_stock_value: max_stock_value} = payload

    available_stock_values =
      @stock_value_spaces
      |> Enum.take_while(&(&1 <= max_stock_value))

    maybe_rigged_company_bid = Enum.find(rigged_auctions, &(&1[:company] == company))

    stock_value =
      if maybe_rigged_company_bid[:rubles] do
        Enum.at(available_stock_values, -1)
      else
        available_stock_values
        |> Enum.random()
      end

    set_stock_value(player, company, stock_value)
    |> injest_commands(game)
  end

  defp do_rail_link(game, payload, rigged_auctions) do
    %{player: player, company: company, available_links: available_links} = payload

    link =
      if rigged_rail_link = Enum.find(rigged_auctions, &(&1[:company] == company))[:rail_link] do
        true = rigged_rail_link in available_links
        rigged_rail_link
      else
        Enum.random(available_links)
      end

    build_initial_rail_link(player, company, link)
    |> injest_commands(game)
  end

  #########################################################
  # Commands
  #########################################################

  def init_and_add_players(player_count) do
    [
      initialize_game(),
      add_player_commands(player_count)
    ]
    |> handle_commands()
  end

  def add_player_commands(player_count) when player_count in 1..6 do
    [
      add_player("Alice"),
      add_player("Bob"),
      add_player("Charlie"),
      add_player("David"),
      add_player("Eve"),
      add_player("Frank")
    ]
    |> Enum.take(player_count)
  end

  #########################################################
  # Converters
  #########################################################
end
