defmodule Tsr.Message do
  require Logger
  require Tsr.Constants, as: Constants
  alias Ecto.Changeset

  defmodule Entity do
    use Ecto.Type
    def type(), do: :any
    def cast(player) when player in 1..5, do: {:ok, player}
    def cast(company) when Constants.is_company(company), do: {:ok, company}
    def cast(:bank), do: {:ok, :bank}

    def cast(_other) do
      :error
    end

    def load(_), do: {:ok, nil}
    def dump(_), do: {:ok, nil}
  end

  defmodule Player do
    use Ecto.Type
    def type(), do: :integer
    def cast(player) when player in 1..5, do: {:ok, player}
    def cast(_), do: :error
    def load(_), do: {:ok, nil}
    def dump(_), do: {:ok, nil}
  end

  defmodule Rubles do
    use Ecto.Type
    def type(), do: :integer
    def cast(rubles) when is_integer(rubles), do: {:ok, rubles}
    def cast(_), do: :error
    def load(_), do: {:ok, nil}
    def dump(_), do: {:ok, nil}
  end

  defmodule SubMap do
    use Ecto.ParameterizedType
    def type(_), do: :map
    def init(keys), do: %{keys: keys}

    def cast(map, %{keys: keys}) do
      changeset = Tsr.Message.__changeset__(map, keys)

      if changeset.valid? and map_size(map) == length(keys) do
        {:ok, Changeset.apply_changes(changeset)}
      else
        :error
      end
    end

    def load(_, _, _), do: {:ok, nil}
    def dump(_, _, _), do: {:ok, nil}

    def new(keys) do
      Ecto.ParameterizedType.init(__MODULE__, keys)
    end
  end

  def payload_types() do
    %{
      available_links: {:array, {:array, :string}},
      certificate_value: :integer,
      command_id: Ecto.UUID,
      company: :string,
      company_stock_values: {:array, SubMap.new([:company, :stock_value])},
      count: :integer,
      entity: Entity,
      from: Entity,
      game_id: :string,
      income: Rubles,
      link_income: Rubles,
      maybe_error: :string,
      max_stock_value: Rubles,
      min_bid: Rubles,
      note: :string,
      phase: :integer,
      player: Player,
      player_name: :string,
      player_order: {:array, Player},
      players: {:array, Player},
      public_cert_count: :integer,
      rail_link: {:array, :string},
      reason: :string,
      reasons: {:array, :string},
      rubles: Rubles,
      score: :integer,
      start_player: Player,
      stock_count: :integer,
      stock_value: Rubles,
      to: Entity,
      total_value: Rubles,
      value_per: Rubles
    }
  end

  def __changeset__(payload, keys, custom_fields \\ []) do
    payload_types =
      Enum.reduce(custom_fields, payload_types(), fn {key, sub_keys}, types ->
        Map.put(types, key, {:array, SubMap.new(sub_keys)})
      end)

    required_keys = Enum.reject(keys, &(&1 == :maybe_error))

    {%{}, payload_types}
    |> Changeset.cast(payload, keys)
    |> Changeset.validate_required(required_keys)
    |> Changeset.validate_inclusion(:company, Constants.companies())
    |> Changeset.validate_number(:count, greater_than_or_equal_to: 0)
    |> Changeset.validate_number(:income, greater_than: 0)
    |> Changeset.validate_number(:min_bid, greater_than_or_equal_to: 8)
    |> Changeset.validate_inclusion(:phase, 1..2)
    |> Changeset.validate_subset(:players, 1..5)
    |> Changeset.validate_length(:reasons, min: 1)
    |> Changeset.validate_number(:score, greater_than_or_equal_to: 0)
  end

  defp log_errors(message_name, payload, keys) do
    unexpected_keys = Map.keys(payload) -- keys

    if Enum.any?(unexpected_keys) do
      Logger.warning("""
      payload/keys mismatch!
      Message name: #{message_name}
      Payload: #{inspect(payload)}
      Keys: #{inspect(keys)}
      Payload has these unexpected keys: #{inspect(Map.keys(payload) -- keys)}
      """)
    end
  end

  def keys_and_custom_fields(fields) do
    Enum.reduce(fields, {[], []}, fn
      field, {keys, custom_fields} ->
        case field do
          {key, _sub_map_keys} -> {[key | keys], [field | custom_fields]}
          key -> {[key | keys], custom_fields}
        end
    end)
  end

  def keys(fields) do
    {keys, _} = keys_and_custom_fields(fields)
    keys
  end

  def validated_payload!(message_name, payload, fields) do
    {keys, custom_fields} = keys_and_custom_fields(fields)
    payload = Map.new(payload)
    log_errors(message_name, payload, keys)
    changeset = __changeset__(payload, keys, custom_fields)

    if changeset.valid? do
      Changeset.apply_changes(changeset)
    else
      raise ArgumentError, """
      Error building message
      Message name: #{message_name}
      Payload: #{inspect(payload)}
      Errors: #{inspect(changeset.errors)}
      """
    end
  end
end
