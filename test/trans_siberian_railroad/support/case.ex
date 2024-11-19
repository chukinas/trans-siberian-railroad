defmodule TransSiberianRailroad.Case do
  use ExUnit.CaseTemplate

  using do
    quote do
      import TransSiberianRailroad.CommandFactory
      import TransSiberianRailroad.GameHelpers
      import TransSiberianRailroad.GameTestHelpers
      alias TransSiberianRailroad.Constants
      alias TransSiberianRailroad.Messages
      taggable_setups()
    end
  end
end
