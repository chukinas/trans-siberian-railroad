defmodule TransSiberianRailroad.ReactionCtx do
  @moduledoc """
  The data available inside a `defreaction` call
  """

  use TypedStruct
  alias TransSiberianRailroad.Command
  alias TransSiberianRailroad.Event
  alias TransSiberianRailroad.Messages
  alias TransSiberianRailroad.Metadata

  typedstruct enforce: true do
    field :projection, struct()
    field :sent_ids, MapSet.t(Ecto.UUID.t())
    field :events, [Event.t()]
    field :commands, [Command.t()]
  end

  ########################################################
  # Constructors
  ########################################################

  def new(projection, sent_id_mapset, events, commands) do
    %__MODULE__{
      projection: projection,
      sent_ids: sent_id_mapset,
      events: events,
      commands: commands
    }
  end

  ########################################################
  # Converters
  ########################################################

  def get_latest_event(%__MODULE__{events: events}, event_name) do
    Enum.find(events, &(&1.name == event_name))
  end

  defp message_sent?(messages, name, trace_id) do
    !!Enum.find(messages, &(&1.name == name and &1.trace_id == trace_id))
  end

  def command_if_unsent(reaction_ctx, command_name, payload \\ %{}, metadata_overrides \\ [])
      when is_list(metadata_overrides) do
    metadata =
      metadata_overrides
      |> Keyword.put_new(:trace_id, reaction_ctx.projection.__trace_id__)
      |> Keyword.put_new(:user, :game)
      |> Metadata.for_command()

    trace_id = Keyword.fetch!(metadata, :trace_id)

    if !message_sent?(reaction_ctx.commands, command_name, trace_id) do
      command = Messages.command(command_name, payload, metadata)
      %{commands: [command]}
    end
  end

  def event_if_unsent(reaction_ctx, event_name, payload \\ %{}, trace_id) do
    if !message_sent?(reaction_ctx.events, event_name, trace_id) do
      Messages.event_builder(event_name, payload)
    end
  end

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
