defmodule TransSiberianRailroad.Aggregator do
  @moduledoc """
  An aggregator is responsible for emitting new events.
  It does this by building a projection from the current events list, then:
  - handling commands that may have been issued by the user or the game itself, or
  - emitting new events ("reactions") based on that current projection.
  """

  defmacro __using__(_) do
    quote do
      use TransSiberianRailroad.CommandHandling
      use TransSiberianRailroad.Reaction
      import TransSiberianRailroad.Aggregator, only: :macros
    end
  end

  defmacro aggregator_typedstruct(opts \\ [], do: block) do
    opts = Keyword.put_new(opts, :opaque, true)

    quote do
      typedstruct unquote(opts) do
        projection_fields()
        field :flags, [term()], default: []
        unquote(block)
      end
    end
  end
end
