defmodule TransSiberianRailroad.Command do
  use TypedStruct
  alias TransSiberianRailroad.Player

  typedstruct enforce: true do
    field :name, String.t()
    field :payload, map()
    field :id, Ecto.UUID.t()
    field :trace_id, Ecto.UUID.t()
    field :user, :game | Player.id()

    # This is only ever set by the Game module,
    # when a command or event is moved from its queue to its history.
    field :global_version, pos_integer(), enforce: false
  end

  defmacro __using__(_) do
    quote do
      import unquote(__MODULE__)
      Module.register_attribute(__MODULE__, :__command_names__, accumulate: true)
      @before_compile unquote(__MODULE__)
    end
  end

  defmacro __before_compile__(_env) do
    quote do
      def command_names(), do: @__command_names__
    end
  end

  defimpl Inspect do
    import Inspect.Algebra

    def inspect(command, opts) do
      payload = Map.to_list(command.payload || %{})
      short_id = String.slice(command.id, 0, 4)
      concat(["#Cmmnd.#{short_id}.#{command.name}<", Inspect.List.inspect(payload, opts), ">"])
    end
  end

  defmacro defcommand(function_name) do
    quote do
      defcommand unquote(function_name)() do
        []
      end
    end
  end

  defmacro defcommand(function_head, do: block) do
    modify_function_args = fn {fn_name, meta, args} ->
      meta =
        if Enum.any?(args) do
          {_, meta, _} = Enum.at(args, -1)
          meta
        else
          meta
        end

      metadata_arg = {:\\, meta, [{:metadata, meta, nil}, []]}
      new_args = args ++ [metadata_arg]
      {fn_name, meta, new_args}
    end

    command_name =
      case function_head do
        {:when, _, stuff} -> hd(stuff)
        _ -> function_head
      end
      |> elem(0)
      |> to_string()

    function_head =
      case function_head do
        {:when, _, _} ->
          update_in(function_head, [Access.elem(2), Access.at(0)], modify_function_args)

        _ ->
          modify_function_args.(function_head)
      end

    quote do
      @__command_name__ unquote(command_name)
      @__command_names__ @__command_name__
      def unquote(function_head) do
        metadata = var!(metadata)

        user =
          case Keyword.fetch(metadata, :user) do
            {:ok, user} ->
              user

            :error ->
              raise """
              Commands must have a :user key in the metadata arg.
              command name: #{inspect(@__command_name__)}
              metadata: #{inspect(metadata)}
              """
          end

        %unquote(__MODULE__){
          name: @__command_name__,
          payload: Map.new(unquote(block)),
          id: metadata[:id] || Ecto.UUID.generate(),
          trace_id: metadata[:trace_id] || Ecto.UUID.generate(),
          user: Keyword.fetch!(metadata, :user)
        }
      end
    end
  end
end
