defmodule TransSiberianRailroad.Aggregator.PlayerAction.BuildRailLink do
  @moduledoc """
  Handles the `build_rail_link` command, ultimately emitting either a `rail_link_built` or `rail_link_rejected` event.
  """

  use TransSiberianRailroad.Aggregator

  aggregator_typedstruct do
    # Invariant: these two fields are either nil or non-nil
    field :current_event, Command.t()
    field :commands, [Command.t(), ...]

    field :next_event, (Metadata.t() -> Event.t())
  end

  ########################################################
  # Begin sequence
  ########################################################

  handle_command "build_rail_link", ctx do
    if ctx.projection.current_event do
      %{player: player, company: company, rail_link: rail_link} = ctx.payload
      reason = "Another rail link is already being built"

      &Messages.rail_link_rejected(
        player,
        company,
        rail_link,
        reason,
        &1
      )
    else
      %{player: player, company: company, rail_link: rail_link} = ctx.payload
      &Messages.rail_link_sequence_begun(player, company, rail_link, &1)
    end
  end

  handle_event "rail_link_sequence_begun", ctx do
    commands =
      [
        Messages.reserve_player_action(ctx.payload.player,
          user: :game,
          trace_id: ctx.event.trace_id
        )
      ]
      |> Enum.shuffle()

    [
      current_event: ctx.event,
      commands: commands
    ]
  end

  defreaction maybe_issue_commands(%{projection: projection} = reaction_ctx) do
    if commands = projection.commands do
      ReactionCtx.issue_unsent_commands(reaction_ctx, commands)
    end
  end

  ########################################################
  # Handle responses
  ########################################################

  handle_event "player_action_reserved", ctx do
    [commands: rm_command(ctx.projection, "reserve_player_action")]
  end

  handle_event "player_action_rejected", ctx do
    [
      commands: rm_command(ctx.projection, "reserve_player_action"),
      next_event: rail_link_rejected(ctx.projection, ctx.payload.reason)
    ]
  end

  defp rm_command(%__MODULE__{current_event: event, commands: commands}, command_name) do
    Enum.reject(commands, fn command ->
      command.name == command_name and command.trace_id == event.trace_id
    end)
  end

  defp rail_link_rejected(projection, reason) do
    %{player: player, company: company, rail_link: rail_link} = projection.current_event.payload
    &Messages.rail_link_rejected(player, company, rail_link, reason, &1)
  end

  ########################################################
  # End sequence
  ########################################################

  defreaction(maybe_issue_event(%{projection: projection}), do: projection.next_event)
  handle_event("rail_link_built", _ctx, do: clear())
  handle_event("rail_link_rejected", _ctx, do: clear())

  defp clear() do
    [
      current_event: nil,
      commands: nil,
      next_event: nil
    ]
  end
end
