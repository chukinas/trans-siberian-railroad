defmodule TransSiberianRailroad.CommandFactory do
  alias TransSiberianRailroad.Messages
  import Messages, only: [command: 2, command: 3]

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
end
