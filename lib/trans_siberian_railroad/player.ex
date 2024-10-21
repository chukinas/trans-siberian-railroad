defmodule TransSiberianRailroad.Player do
  @type id() :: 1..5
  defguard is_id(x) when x in 1..5
end
