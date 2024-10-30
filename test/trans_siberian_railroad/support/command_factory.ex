defmodule TransSiberianRailroad.CommandFactory do
  alias TransSiberianRailroad.Messages

  def initialize_game() do
    Messages.initialize_game(user: 1)
  end

  def add_player(player_name) do
    Messages.add_player(player_name, user: Ecto.UUID.generate())
  end

  def set_start_player(player_id) do
    Messages.set_start_player(player_id, user: Ecto.UUID.generate())
  end

  def set_player_order(player_order) do
    Messages.set_player_order(player_order, user: Ecto.UUID.generate())
  end

  def start_game() do
    Messages.start_game(user: Ecto.UUID.generate())
  end

  def pass_on_company(player_id, company) do
    Messages.pass_on_company(player_id, company, user: player_id)
  end

  def submit_bid(player_id, company, amount) do
    Messages.submit_bid(player_id, company, amount, user: player_id)
  end

  def set_stock_value(player_id, company, price) do
    Messages.set_stock_value(player_id, company, price, user: player_id)
  end

  def pass(player_id) do
    Messages.pass(player_id, user: player_id)
  end

  def purchase_single_stock(purchasing_player, company, price) do
    Messages.purchase_single_stock(purchasing_player, company, price, user: purchasing_player)
  end
end
