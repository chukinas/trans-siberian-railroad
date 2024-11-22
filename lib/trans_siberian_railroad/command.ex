defmodule TransSiberianRailroad.Command do
  use TypedStruct
  alias TransSiberianRailroad.Constants
  alias TransSiberianRailroad.Message
  alias TransSiberianRailroad.Metadata

  #########################################################
  # Struct
  #########################################################

  typedstruct enforce: true do
    field :name, String.t()
    field :payload, map()
    field :id, Ecto.UUID.t()
    field :trace_id, Ecto.UUID.t()
    field :user, :game | Constants.player()

    # This is only ever set by the Game module,
    # when a command or event is moved from its queue to its history.
    field :global_version, pos_integer(), enforce: false
  end

  defimpl Inspect do
    import Inspect.Algebra

    def inspect(command, opts) do
      payload = Map.to_list(command.payload || %{})
      short_id = String.slice(command.id, 0, 4)
      concat(["#Cmmnd.#{short_id}.#{command.name}<", Inspect.List.inspect(payload, opts), ">"])
    end
  end

  #########################################################
  # Metaprogramming
  #########################################################

  defmacro __using__(_) do
    quote do
      import unquote(__MODULE__)
      Module.register_attribute(__MODULE__, :__commands__, accumulate: true)
      @before_compile unquote(__MODULE__)
    end
  end

  defmacro defcommand(command_name, keys \\ []) do
    quote do
      if Enum.find(@__commands__, &(elem(&1, 0) == unquote(command_name))) do
        raise """
        Command #{unquote(command_name)} has already been defined.
        """
      end

      @__commands__ {unquote(command_name), unquote(keys)}
    end
  end

  defmacro __before_compile__(_env) do
    quote do
      @command_names_and_keys Map.new(@__commands__)
      def command(command_name, payload \\ %{}, metadata) do
        keys = Map.fetch!(@command_names_and_keys, command_name)
        unquote(__MODULE__).__new__(command_name, payload, keys, metadata)
      end

      @command_names Map.keys(@command_names_and_keys)
      def command_names() do
        @command_names
      end
    end
  end

  #########################################################
  # Other
  #########################################################

  def __new__(command_name, payload, keys, metadata) when is_list(keys) do
    metadata = Metadata.for_command(metadata, []) |> Map.new()

    %__MODULE__{
      id: metadata.id,
      name: command_name,
      payload: Message.validated_payload!(command_name, payload, keys),
      trace_id: metadata.trace_id,
      user: metadata.user
    }
  end
end
