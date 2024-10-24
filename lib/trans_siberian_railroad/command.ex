defmodule TransSiberianRailroad.Command do
  use TypedStruct

  typedstruct enforce: true do
    field :name, String.t()
    field :payload, map()
    field :trace_id, Ecto.UUID.t()
  end

  defimpl Inspect do
    import Inspect.Algebra

    def inspect(command, opts) do
      payload = Map.to_list(command.payload || %{})
      concat(["#Command.#{command.name}<", Inspect.List.inspect(payload, opts), ">"])
    end
  end
end
