defmodule Tsr.RandomGame do
  use TypedStruct
  alias Tsr.Event
  alias Tsr.Game
  alias Tsr.Messages
  alias Tsr.Players
  import Messages, only: [command: 2, command: 3]

  typedstruct enforce: true, module: RailLink do
    field :company, String.t()
    field :rail_link, [String.t()]
  end

  typedstruct enforce: true, module: Player do
    field :number, 1..5
    field :current?, boolean(), default: false
  end

  typedstruct enforce: true do
    field :player_count, 3..5
    field :players, [Player.t()], default: []
    field :rail_links, [RailLink.t()], default: []
  end

  def new() do
    {:ok, context} = start_game(%{})
    game = Keyword.fetch!(context, :game)
    _game = do_rand_auction_phase(game, [])
    player_count = Keyword.fetch!(context, :player_count)
    current_player = Enum.random(1..player_count)

    players =
      for player <- 1..player_count do
        %Player{number: player, current?: player == current_player}
      end

    %__MODULE__{
      player_count: player_count,
      players: players,
      rail_links: [%RailLink{company: "red", rail_link: ~w(moscow stpetersburg)}]
    }
  end

  #########################################################
  # Converters
  #########################################################

  #########################################################
  # from GameHelpers
  # TODO DRY out
  #########################################################

  def handle_commands(game \\ Game.new(), commands, opts \\ []) do
    commands =
      commands
      |> List.flatten()
      |> Enum.reject(&is_nil/1)

    if Keyword.get(opts, :one_by_one, true) do
      Enum.reduce(commands, game, &handle_one_command(&2, &1))
    else
      Enum.reduce(commands, game, &Game.queue_command(&2, &1))
      |> Game.execute()
    end
  end

  def handle_one_command(game \\ Game.new(), command) do
    game
    |> Game.queue_command(command)
    |> Game.execute()
  end

  def current_money(game, player) do
    Enum.reduce(game.events, 0, fn event, balance ->
      case event.name do
        "rubles_transferred" ->
          rubles =
            Enum.find_value(event.payload.transfers, fn
              %{entity: ^player, rubles: rubles} -> rubles
              _ -> nil
            end) || 0

          balance + rubles

        _ ->
          balance
      end
    end)
  end

  def injest_commands(command_or_commands, game, opts \\ []) do
    handle_commands(game, List.wrap(command_or_commands), opts)
  end

  #########################################################
  # from GameTestHelpers
  # TODO DRY out?
  #########################################################

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
  # from GameTestHelpers
  # Random Auction Phase 1
  #########################################################

  # TODO
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

  @stock_value_spaces [8..48//4, 50..70//2, [75]]
                      |> Enum.map(&Enum.to_list/1)
                      |> List.flatten()
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
  # copied from CommandFactory
  # TODO
  #########################################################

  def initialize_game() do
    game_id =
      1..4
      |> Enum.map(fn _ -> Enum.random(?A..?Z) end)
      |> to_string()

    command("initialize_game", [game_id: game_id], user: 1)
  end

  def add_player(player_name) do
    command("add_player", [player_name: player_name], user: Ecto.UUID.generate())
  end

  def set_start_player(player) do
    command("set_start_player", [player: player], user: Ecto.UUID.generate())
  end

  def set_player_order(player_order) do
    payload = [player_order: player_order]
    command("set_player_order", payload, user: Ecto.UUID.generate())
  end

  def start_game() do
    command("start_game", user: Ecto.UUID.generate())
  end

  def pass_on_company(player, company) do
    command("pass_on_company", [player: player, company: company], user: player)
  end

  def submit_bid(player, company, rubles) do
    payload = [player: player, company: company, rubles: rubles]
    command("submit_bid", payload, user: player)
  end

  def build_initial_rail_link(player, company, rail_link) do
    payload = [player: player, company: company, rail_link: rail_link]
    command("build_initial_rail_link", payload, user: player)
  end

  def set_stock_value(player, company, stock_value) do
    payload = [player: player, company: company, stock_value: stock_value]
    command("set_stock_value", payload, user: player)
  end

  def build_internal_rail_link(player, company, rail_link) do
    payload = [player: player, company: company, rail_link: rail_link]
    command("build_internal_rail_link", payload, user: player)
  end

  def build_external_rail_link(player, company, rail_link) do
    payload = [player: player, company: company, rail_link: rail_link]
    command("build_external_rail_link", payload, user: player)
  end

  def pass(player) do
    command("pass", [player: player], user: player)
  end

  def purchase_single_stock(player, company, rubles) do
    payload = [player: player, company: company, rubles: rubles]
    command("purchase_single_stock", payload, user: player)
  end

  def check_phase_shift() do
    command("check_phase_shift", user: :game)
  end
end
