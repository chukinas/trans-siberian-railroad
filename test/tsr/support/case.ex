defmodule Tsr.Case do
  use ExUnit.CaseTemplate

  using do
    quote do
      import Tsr.CommandFactory
      import Tsr.GameHelpers
      import Tsr.GameTestHelpers
      alias Tsr.Constants
      alias Tsr.Messages
      import Messages, only: [command: 2, command: 3]
      taggable_setups()
    end
  end
end
