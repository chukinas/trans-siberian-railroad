defmodule TransSiberianRailroad.ReactionCtx do
  @moduledoc """
  The data available inside a `defreaction` call
  """

  use TypedStruct
  alias TransSiberianRailroad.Command
  alias TransSiberianRailroad.Event

  typedstruct enforce: true do
    field :projection, struct()
    field :sent_ids, MapSet.t(Ecto.UUID.t())
  end

  ########################################################
  # Constructors
  ########################################################

  def new(projection, sent_id_mapset) do
    %__MODULE__{projection: projection, sent_ids: sent_id_mapset}
  end

  ########################################################
  # Converters
  ########################################################

  def if_uuid_unsent(reaction_ctx, event_id, fun) do
    if unsent_id?(reaction_ctx, event_id) do
      fun.()
    end
  end

  def issue_if_unsent(reaction_ctx, message) do
    if unsent_id?(reaction_ctx, message.id) do
      case message do
        %Command{} -> %{commands: [message]}
        %Event{} -> %{events: [message]}
      end
    end
  end

  def issue_unsent_commands(reaction_ctx, commands) when is_list(commands) do
    unsent_commands = Enum.filter(commands, &unsent_id?(reaction_ctx, &1.id))

    case unsent_commands do
      [] -> nil
      _ -> %{commands: unsent_commands}
    end
  end

  def unsent_id?(%__MODULE__{sent_ids: sent_ids}, id) do
    !MapSet.member?(sent_ids, id)
  end
end
