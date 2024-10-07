defmodule TransSiberianRailroad.Events do
  @moduledoc """
  This module is a collection of all a game's events.
  """

  alias TransSiberianRailroad.Event

  # Event events are in descending order.
  # In other words, the head of the list if the lastest (most recent) event.
  # TODO that's probably going to change since I think we have to
  # rip through this more often that we add something to the tail.
  # TODO make this opaque
  @type t() :: [Event.t()]

  # TODO extract zero-index to a constant
  def next_sequence_number(events) do
    length(events)
  end
end
