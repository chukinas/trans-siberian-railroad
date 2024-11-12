defmodule TransSiberianRailroad.Aggregator.GameEndSequence do
  @moduledoc """
  Determines the winner of the game after the game ends.

  The end-game conditions are handled elsewhere.
  """
  use TransSiberianRailroad.Aggregator
  use TransSiberianRailroad.Projection
  alias TransSiberianRailroad.Messages

  aggregator_typedstruct do
  end

  handle_command "end_game", ctx do
    %{causes: causes} = ctx.payload
    &Messages.game_end_sequence_begun(causes, &1)
  end
end
