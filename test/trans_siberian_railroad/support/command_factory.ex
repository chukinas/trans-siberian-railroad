defmodule TransSiberianRailroad.CommandFactory do
  alias TransSiberianRailroad.Messages

  def initialize_game() do
    Messages.initialize_game(user: 1)
  end

  def add_player(player_name) do
    Messages.add_player(player_name, user: Ecto.UUID.generate())
  end

  def set_start_player(player) do
    Messages.set_start_player(player, user: Ecto.UUID.generate())
  end

  def set_player_order(player_order) do
    Messages.set_player_order(player_order, user: Ecto.UUID.generate())
  end

  def start_game() do
    Messages.start_game(user: Ecto.UUID.generate())
  end

  def pass_on_company(player, company) do
    Messages.pass_on_company(player, company, user: player)
  end

  def submit_bid(player, company, amount) do
    Messages.submit_bid(player, company, amount, user: player)
  end

  def build_rail_link(player, company, cities) do
    Messages.build_rail_link(player, company, cities, user: player)
  end

  def set_stock_value(player, company, price) do
    Messages.set_stock_value(player, company, price, user: player)
  end

  def pass(player) do
    Messages.pass(player, user: player)
  end

  def purchase_single_stock(purchasing_player, company, price) do
    Messages.purchase_single_stock(purchasing_player, company, price, user: purchasing_player)
  end
end
