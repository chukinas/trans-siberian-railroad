defmodule TransSiberianRailroad.Reactions do
  @moduledoc """
  Abstraction for defining reactions.
  """

  alias TransSiberianRailroad.ReactionCtx

  def set_next_command(command) do
    [next_command: command]
  end

  def __maybe_next_command__(projection, reaction_ctx) do
    if command = projection.next_command do
      ReactionCtx.issue_if_unsent(reaction_ctx, command)
    end
  end

  use TypedStruct.Plugin
  @impl true
  defmacro init(_opts) do
    quote do
      field :next_command, TransSiberianRailroad.Command.t()

      defdelegate set_next_command(command), to: unquote(__MODULE__)

      defreaction __maybe_next_command__(reaction_ctx) do
        unquote(__MODULE__).__maybe_next_command__(reaction_ctx.projection, reaction_ctx)
      end
    end
  end
end
