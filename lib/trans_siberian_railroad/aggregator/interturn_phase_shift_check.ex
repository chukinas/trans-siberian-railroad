defmodule TransSiberianRailroad.Aggregator.Interturn.PhaseShiftCheck do
  @moduledoc """
  Each Interturn, if we're still in Phase 1, we check if any company has a stock value of 48 or more.
  This triggers Phase 2.

  Reference p11 of the rulebook.
  """
  use TransSiberianRailroad.Aggregator

  aggregator_typedstruct do
  end

  handle_command "check_phase_shift", _ctx do
    Messages.event_builder("phase_2_started")
  end
end
