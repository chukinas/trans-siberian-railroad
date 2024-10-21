defmodule TransSiberianRailroad.GameTestHelpers do
  alias TransSiberianRailroad.Game
  alias TransSiberianRailroad.Event
  alias TransSiberianRailroad.Messages
  alias TransSiberianRailroad.Players

  @phase_1_companies ~w/red blue green yellow/a
  @stock_value_spaces [8..48//4, 50..70//2, [75]]
                      |> Enum.map(&Enum.to_list/1)
                      |> List.flatten()

  #########################################################
  # Setups
  #########################################################

  # TODO mv to end of setups
  # Requires start_game to be run first.
  def random_first_auction_phase(context) do
    player_count = context.player_count

    new_context = [
      start_player: context.start_player,
      game: context.game,
      one_round: context.one_round
    ]

    Enum.reduce(@phase_1_companies, new_context, fn company, new_context ->
      [start_player: start_player, game: game, one_round: one_round] = new_context
      player_balances = Map.new(1..player_count, &{&1, current_money(game, &1)})

      player_bids =
        Enum.map(player_balances, fn {player_id, balance} ->
          bid = if balance >= 8, do: Enum.random(8..balance)
          {player_id, bid}
        end)

      {auction_winner, bid} = Enum.random(player_bids)

      start_player =
        if bid do
          auction_winner
        else
          start_player
        end

      commands =
        Enum.map(one_round, fn player_id ->
          if player_id == auction_winner and not is_nil(bid) do
            Messages.submit_bid(player_id, company, bid)
          else
            Messages.pass_on_company(player_id, company)
          end
        end)

      commands =
        if bid do
          # TODO this should 'take until'.
          # TOOD so should the StockPrice function
          price = @stock_value_spaces |> Enum.filter(&(&1 <= bid)) |> Enum.random()
          # TODO make sure the arg is named stock_price or something like that
          [commands, Messages.set_starting_stock_price(auction_winner, company, price)]
        else
          commands
        end

      game = Game.handle_commands(game, commands)
      one_round = Players.one_round(context.player_order, start_player)
      [start_player: start_player, game: game, one_round: one_round]
    end)
  end

  def start_game(context) do
    player_count = context[:player_count] || Enum.random(3..5)
    start_player = context[:starting_player] || Enum.random(1..player_count)
    player_order = Enum.to_list(context[:player_order] || Enum.shuffle(1..player_count))
    one_round = Players.one_round(player_order, start_player)

    game =
      Game.handle_commands([
        Messages.initialize_game(),
        add_player_commands(player_count),
        Messages.set_start_player(start_player),
        Messages.set_player_order(player_order),
        Messages.start_game()
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
      Game.handle_commands(
        context.game,
        for player_id <- context.one_round do
          if player_id == auction_winner do
            Messages.submit_bid(player_id, :red, amount)
          else
            Messages.pass_on_company(player_id, :red)
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
  # Commands
  #########################################################

  def add_player_commands(player_count) when player_count in 1..6 do
    [
      Messages.add_player("Alice"),
      Messages.add_player("Bob"),
      Messages.add_player("Charlie"),
      Messages.add_player("David"),
      Messages.add_player("Eve"),
      Messages.add_player("Frank")
    ]
    |> Enum.take(player_count)
  end

  #########################################################
  # State (Events) Converters
  #########################################################

  def player_order(events) do
    fetch_single_event_payload!(events, "player_order_set").player_order
  end

  def starting_player(events) do
    fetch_single_event_payload!(events, "start_player_set").start_player
  end

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
  # Money
  #########################################################

  # TODO add a function that returns all players' money balances
  def current_money(game, player_id) do
    Enum.reduce(game.events, 0, fn event, balance ->
      case event.name do
        "money_transferred" ->
          amount = Map.get(event.payload.transfers, player_id, 0)
          balance + amount

        _ ->
          balance
      end
    end)
  end
end
