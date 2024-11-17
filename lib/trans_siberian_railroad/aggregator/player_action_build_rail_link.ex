defmodule TransSiberianRailroad.Aggregator.PlayerAction.BuildRailLink do
  @moduledoc """
  Handles the `build_rail_link` command, ultimately emitting either a `rail_link_built` or `rail_link_rejected` event.
  """

  use TransSiberianRailroad.Aggregator

  aggregator_typedstruct do
    # The rail_link_sequence_begun is stored here.
    # This field being non-nil tells us that the sequence is in progress.
    field :current_event, Command.t()

    # We issue commands and wait for their responses
    field :validation_commands, [Command.t()], default: []

    # Those responses are collected here.
    field :errors, [String.t()], default: []
  end

  ########################################################
  # Begin sequence
  ########################################################

  handle_command "build_rail_link", ctx do
    if ctx.projection.current_event do
      %{player: player, company: company, rail_link: rail_link} = ctx.payload
      reason = "another rail link is already being built"

      &Messages.rail_link_rejected(
        player,
        company,
        rail_link,
        [reason],
        &1
      )
    else
      %{player: player, company: company, rail_link: rail_link} = ctx.payload
      &Messages.rail_link_sequence_begun(player, company, rail_link, &1)
    end
  end

  handle_event "rail_link_sequence_begun", ctx do
    metadata = [user: :game, trace_id: ctx.event.trace_id]

    validation_commands =
      [
        Messages.reserve_player_action(ctx.payload.player, metadata),
        Messages.check_is_company_public(ctx.payload.company, metadata)
      ]
      |> Enum.shuffle()

    [
      current_event: ctx.event,
      validation_commands: validation_commands,
      errors: []
    ]
  end

  defreaction maybe_issue_commands(%{projection: projection} = reaction_ctx) do
    ReactionCtx.issue_unsent_commands(reaction_ctx, projection.validation_commands)
  end

  ########################################################
  # Handle validation responses
  ########################################################

  defp rm_command(
         %__MODULE__{current_event: event, validation_commands: validation_commands},
         command_name
       ) do
    Enum.reject(validation_commands, fn command ->
      command.name == command_name and command.trace_id == event.trace_id
    end)
  end

  # ------------------------------------------------------
  # It must be this player's turn
  # ------------------------------------------------------

  handle_event "player_action_reserved", ctx do
    [validation_commands: rm_command(ctx.projection, "reserve_player_action")]
  end

  handle_event "player_action_rejected", ctx do
    error = ctx.payload.reason

    [
      validation_commands: rm_command(ctx.projection, "reserve_player_action"),
      errors: [error | ctx.projection.errors]
    ]
  end

  # ------------------------------------------------------
  # Company must be public
  # ------------------------------------------------------

  handle_event "company_is_public", ctx do
    [validation_commands: rm_command(ctx.projection, "check_is_company_public")]
  end

  handle_event "company_is_not_public", ctx do
    error = "company is not public"

    [
      validation_commands: rm_command(ctx.projection, "check_is_company_public"),
      errors: [error | ctx.projection.errors]
    ]
  end

  ########################################################
  # End sequence
  ########################################################

  defreaction maybe_issue_event(reaction_ctx) do
    projection = reaction_ctx.projection

    case projection do
      %__MODULE__{current_event: %Event{}, validation_commands: [], errors: []} ->
        raise "not yet implemented"

      %__MODULE__{
        current_event: %Event{payload: payload},
        validation_commands: [],
        errors: errors
      } ->
        %{player: player, company: company, rail_link: rail_link} = payload
        &Messages.rail_link_rejected(player, company, rail_link, errors, &1)

      _ ->
        nil
    end
  end

  handle_event("rail_link_built", _ctx, do: clear())

  handle_event "rail_link_rejected", ctx do
    with %Event{trace_id: trace_id} <- ctx.projection.current_event,
         ^trace_id <- ctx.event.trace_id do
      clear()
    else
      _ -> nil
    end
  end

  defp clear() do
    [
      current_event: nil,
      validation_commands: [],
      errors: []
    ]
  end
end
