defmodule TransSiberianRailroad.Projection do
  @moduledoc """
  A projection is a read model of the domain events.
  It takes a list of those events and reduces them into a single struct.
  This internals of this struct should never be public knowledge.
  It exists only to allow that struct's module to make decisions about what new events to emit.

  This module *could* have been part of TransSiberianRailroad.Aggregator,
  but the projection concerns are atomic enough that it justified its own module.
  Plus, perhaps in the future, we'll want to project events into read models that are used
  e.g. to power the front end.
  """

  require TransSiberianRailroad.Messages, as: Messages
  alias TransSiberianRailroad.Event
  alias TransSiberianRailroad.Metadata

  defmacro __using__(_opts) do
    quote do
      use TypedStruct
      alias unquote(__MODULE__)
      @before_compile unquote(__MODULE__)
      Module.register_attribute(__MODULE__, :handle_event_names, accumulate: true)

      import TransSiberianRailroad.Projection, only: [handle_event: 3, projection_fields: 0]
    end
  end

  def project(projection_mod, events \\ []) do
    initial_projection = struct!(projection_mod)

    events
    |> Enum.sort(Event)
    |> Enum.reduce(initial_projection, &(project_event(&2, &1) |> elem(1)))
  end

  def project_event(%projection_mod{} = projection, %Event{} = event) do
    projection = put_version(projection, event)
    %Event{name: event_name, payload: payload} = event

    if event_name in projection_mod.__handled_event_names__() do
      ctx = %{
        projection: projection,
        payload: payload,
        trace_id: event.trace_id,
        event_id: event.id
      }

      fields = projection_mod.__handle_event__(event_name, ctx) |> List.wrap()

      projection =
        struct!(projection, fields)
        |> put_trace_id(event)

      {:modified, projection}
    else
      {:unchanged, projection}
    end
  end

  #########################################################
  # Event Handling
  #########################################################

  @doc """
  This is how projection modules define event handlers.
  """
  defmacro handle_event(event_name, ctx, do: block) do
    quote do
      event_name = unquote(event_name)
      @handle_event_names event_name

      valid_event_names = Messages.event_names()

      unless event_name in valid_event_names do
        raise """
        handle_event/3 expects an event name already declared in #{inspect(Messages)}.

        name: #{inspect(event_name)}

        valid names:
        #{inspect(valid_event_names)}
        """
      end

      def __handle_event__(unquote(event_name), unquote(ctx)) do
        unquote(block)
      end
    end
  end

  defmacro __before_compile__(_env) do
    quote do
      def __handled_event_names__(), do: @handle_event_names
    end
  end

  #########################################################
  # Metadata
  #########################################################

  defmacro projection_fields() do
    quote do
      field :__version__, non_neg_integer(), required: true, default: 0
      field :__trace_id__, Ecto.UUID.t(), enforce: false
    end
  end

  def next_metadata(%_{__version__: version, __trace_id__: trace_id}, offset \\ 0) do
    next_version = version + 1 + offset
    Metadata.new(next_version, trace_id)
  end

  defp put_version(%_{__version__: current_version} = projection, %Event{version: next_version})
       when current_version + 1 == next_version do
    struct!(projection, __version__: next_version)
  end

  defp put_trace_id(%_{} = projection, %Event{trace_id: trace_id}) do
    struct!(projection, __trace_id__: trace_id)
  end

  def metadata(%_{__version__: version, __trace_id__: trace_id}, overrides \\ []) do
    next_version = version + 1 + Keyword.get(overrides, :offset, 0)
    id = Keyword.get(overrides, :id, Ecto.UUID.generate())

    metadata =
      Metadata.new(next_version, trace_id)
      |> Keyword.put(:id, id)

    if user = Keyword.get(overrides, :user) do
      Keyword.put(metadata, :user, user)
    else
      metadata
    end
  end
end
