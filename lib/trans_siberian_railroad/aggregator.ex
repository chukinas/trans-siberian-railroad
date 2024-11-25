defmodule Tsr.Aggregator do
  @moduledoc """
  An aggregator is responsible for emitting new events.
  It does this by building a projection from the current events list, then:
  - handling commands that may have been issued by the user or the game itself, or
  - emitting new events ("reactions") based on that current projection.
  """

  defmacro __using__(_) do
    quote do
      use Tsr.CommandHandling
      use Tsr.Projection
      use Tsr.Reaction
      import Tsr.Aggregator, only: :macros
      require Tsr.Constants, as: Constants
      alias Tsr.Command
      alias Tsr.Event
      alias Tsr.Messages
      import Messages, only: [command: 2, command: 3, event_builder: 1, event_builder: 2]
      alias Tsr.Metadata
      alias Tsr.ReactionCtx
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
