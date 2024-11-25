defmodule Tsr.IncomeTest do
  use ExUnit.Case, async: true
  alias Tsr.Income

  test "There are 11 stock-value-increase spaces" do
    assert 11 == Income.count_stock_value_increases(2, 70)
  end

  test "Increasing exactly to a stock-value-increase space increases stock value" do
    assert 1 == Income.count_stock_value_increases(9, 10)
  end

  test "Increasing from 10 to 11 does not increase stock value" do
    assert 0 == Income.count_stock_value_increases(10, 11)
  end
end
