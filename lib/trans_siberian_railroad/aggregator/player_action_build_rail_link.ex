defmodule Tsr.Aggregator.PlayerAction.BuildRailLink do
  @moduledoc """
  Handles the `build_internal_rail_link` command, ultimately emitting either a `internal_rail_link_built` or `internal_rail_link_rejected` event.
  """

  use Tsr.Aggregator

  aggregator_typedstruct do
    # The internal_rail_link_sequence_started is stored here.
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

  handle_command "build_internal_rail_link", ctx do
    if ctx.projection.current_event do
      reason = "another rail link is already being built"

      Messages.event_builder(
        "internal_rail_link_rejected",
        Map.put(ctx.payload, :reasons, [reason])
      )
    else
      Messages.event_builder("internal_rail_link_sequence_started", ctx.payload)
    end
  end

  handle_event "internal_rail_link_sequence_started", ctx do
    metadata = [user: :game, trace_id: ctx.event.trace_id]
    %{player: player, company: company, rail_link: rail_link} = ctx.payload
    rubles = 4

    validation_commands =
      [
        {"reserve_player_action", player: player},
        {"validate_public_company", company: company},
        {"validate_controlling_share", player: player, company: company},
        {"validate_company_money", company: company, rubles: rubles},
        {"validate_company_rail_link", company: company, rail_link: rail_link}
      ]
      |> Enum.map(fn {n, kv} -> command(n, kv, metadata) end)
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

  defp update_commands_and_errors(event_ctx, command_name, error_msg \\ nil) do
    %__MODULE__{current_event: current_event, validation_commands: validation_commands} =
      event_ctx.projection

    validation_commands =
      Enum.reject(validation_commands, fn command ->
        command.name == command_name and command.trace_id == current_event.trace_id
      end)

    if error_msg do
      errors = [error_msg | event_ctx.projection.errors]
      [validation_commands: validation_commands, errors: errors]
    else
      [validation_commands: validation_commands]
    end
  end

  # It must be this player's turn
  handle_event "player_action_reserved", ctx do
    update_commands_and_errors(ctx, "reserve_player_action")
  end

  handle_event "player_action_rejected", ctx do
    update_commands_and_errors(ctx, "reserve_player_action", ctx.payload.reason)
  end

  # Company must be public
  handle_event "public_company_validated", ctx do
    update_commands_and_errors(ctx, "validate_public_company", ctx.payload[:maybe_error])
  end

  # Player must have controlling share
  handle_event "controlling_share_validated", ctx do
    update_commands_and_errors(ctx, "validate_controlling_share", ctx.payload[:maybe_error])
  end

  # Rail link must connect to network
  handle_event "company_rail_link_validated", ctx do
    update_commands_and_errors(ctx, "validate_company_rail_link", ctx.payload[:maybe_error])
  end

  # Company must have enough rubles
  handle_event "company_money_validated", ctx do
    update_commands_and_errors(ctx, "validate_company_money", ctx.payload[:maybe_error])
  end

  ########################################################
  # End sequence
  ########################################################

  defreaction maybe_issue_event(reaction_ctx) do
    projection = reaction_ctx.projection

    case projection do
      %__MODULE__{current_event: %Event{payload: payload}, validation_commands: [], errors: []} ->
        Messages.event_builder("internal_rail_link_built", payload)

      %__MODULE__{
        current_event: %Event{payload: payload},
        validation_commands: [],
        errors: errors
      } ->
        Messages.event_builder("internal_rail_link_rejected", Map.put(payload, :reasons, errors))

      _ ->
        nil
    end
  end

  handle_event("internal_rail_link_built", _ctx, do: clear())

  handle_event "internal_rail_link_rejected", ctx do
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
