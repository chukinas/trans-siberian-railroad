defmodule TransSiberianRailroad.GameTestHelpers do
  import TransSiberianRailroad.CommandFactory
  import TransSiberianRailroad.GameHelpers
  alias TransSiberianRailroad.Event
  alias TransSiberianRailroad.Players

  @phase_1_companies ~w/red blue green yellow/a
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
          do: rand_auction_phase(context),
          else: :ok
      end
    end
  end

  def start_game(context) do
    player_count = context[:player_count] || Enum.random(3..5)
    start_player = context[:start_player] || Enum.random(1..player_count)
    player_order = Enum.to_list(context[:player_order] || Enum.shuffle(1..player_count))
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
    amount = context[:winning_bid_amount] || 8

    game =
      handle_commands(
        context.game,
        for player_id <- context.one_round do
          if player_id == auction_winner do
            submit_bid(player_id, :red, amount)
          else
            pass_on_company(player_id, :red)
          end
        end
      )

    {:ok,
     game_prior_to_bidding: game_prior_to_bidding,
     auction_winner: auction_winner,
     amount: amount,
     game: game}
  end

  #########################################################
  # Random Auction Phase 1
  #########################################################

  def rand_auction_phase(context) do
    game = do_rand_auction_phase(context.game)
    start_player = fetch_single_event!(game.events, "auction_phase_ended").payload.start_player
    [game: game, start_player: start_player]
  end

  defp do_rand_auction_phase(game) do
    event = hd(game.events)
    payload = event.payload

    case event.name do
      "awaiting_bid_or_pass" -> game |> do_bid_or_pass(payload) |> do_rand_auction_phase()
      "awaiting_stock_value" -> game |> do_stock_value(payload) |> do_rand_auction_phase()
      _ -> game
    end
  end

  defp do_bid_or_pass(game, payload) do
    %{player: player, company: company, min_bid: min_bid} = payload
    player_money = current_money(game, player)

    player_options =
      cond do
        player_money < min_bid -> [nil]
        true -> [nil | Enum.to_list(min_bid..player_money)]
      end

    command =
      case Enum.random(player_options) do
        nil -> pass_on_company(player, company)
        bid -> submit_bid(player, company, bid)
      end

    handle_commands(game, [command])
  end

  defp do_stock_value(game, payload) do
    %{player: player, company: company, max_price: max_price} = payload

    price =
      @stock_value_spaces
      |> Enum.take_while(&(&1 <= max_price))
      |> Enum.random()

    command = set_stock_value(player, company, price)
    handle_commands(game, [command])
  end

  #########################################################
  # Commands
  #########################################################

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
  # State (Events) Converters
  #########################################################

  def fetch_single_event_payload!(events, event_name) do
    fetch_single_event!(events, event_name).payload
  end

  # Succeeds only if there is one such sought event in the list.
  def fetch_single_event!(events, event_name) do
    case filter_events_by_name(events, event_name) do
      [%Event{} = event] -> event
      events -> raise "Expected exactly one #{inspect(event_name)} event; got #{length(events)}."
    end
  end

  def filter_events_by_name(events, event_name, opts \\ []) do
    events = Enum.filter(events, &(&1.name == event_name))

    if opts[:asc] do
      Enum.reverse(events)
    else
      events
    end
  end

  def get_latest_event_by_name(events, event_name) do
    Enum.find(events, &(&1.name == event_name))
  end

  #########################################################
  # Converters
  #########################################################

  def player_order!(game) do
    fetch_single_event!(game.events, "player_order_set").payload.player_order
  end

  def next_player!(game) do
    game.events
    |> Stream.map(&{&1.name, &1.payload})
    |> Enum.find_value(fn
      {"start_player_set", payload} ->
        payload.start_player

      {"player_won_company_auction", payload} ->
        if payload.company in @phase_1_companies, do: payload.player_id

      {"player_turn_started", payload} ->
        payload.player_id

      _ ->
        raise "No next player found."
    end)
  end
end
