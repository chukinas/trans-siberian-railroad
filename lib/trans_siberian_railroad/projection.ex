defmodule TransSiberianRailroad.Projection do
  @moduledoc """
  Aggregators each define a projection,
  where we rip through the events and build up the current state.
  """

  require TransSiberianRailroad.Messages, as: Messages

  defmacro __using__(opts) do
    # TODO refactor stuff until this just always gets injected
    apple =
      unless opts[:exclude_apple] do
        quote do
          defp apple(projection, event_name, payload) do
            unquote(__MODULE__).__handle_event__(__MODULE__, projection, event_name, payload)
          end
        end
      end

    quote do
      @before_compile unquote(__MODULE__)
      Module.register_attribute(__MODULE__, :__handled_event_names__, accumulate: true)
      import TransSiberianRailroad.Projection, only: [handle_event: 3]

      @impl true
      # TODO all aggregators should use this
      # TODO but better yet, if all aggregators move to being structs,
      # then I can implement a protocol instead.
      def put_version(%{last_version: _} = projection, sequence_number) do
        %{projection | last_version: sequence_number}
      end

      unquote(apple)
    end
  end

  defmacro __before_compile__(_env) do
    quote do
      @impl true
      def init(), do: %__MODULE__{}

      # TODO rm
      def handled_event_names(), do: @__handled_event_names__
    end
  end

  # This is a macro ONLY because I want to accumulate the event names
  defmacro handle_event(event_name, ctx, do: block) do
    # TODO unrequire
    unless Messages.valid_event_name?(event_name) do
      raise """
      #{__MODULE__}.handle_event expects an event name already declared in Messages.

      name: #{event_name}

      valid names:
      #{inspect(Messages.event_names())}
      """
    end

    quote do
      @__handled_event_names__ unquote(event_name)
      # TODO I don't want this to be public
      def handle_event3(unquote(event_name), unquote(ctx)) do
        unquote(block)
      end
    end
  end

  def __handle_event__(mod, projection, event_name, payload) do
    if event_name in mod.handled_event_names() do
      ctx = %{
        projection: projection,
        payload: payload
      }

      fields = mod.handle_event3(event_name, ctx)
      struct!(projection, fields)
    else
      projection
    end
  end

  def orange(projection_mod, event) do
    projection = projection_mod.init()
    __handle_event__(projection_mod, projection, event.name, event.payload)
  end
end
