defmodule TransSiberianRailroad.Aggregator.Players do
  @moduledoc """
  Handles the adding of players to the game.

  That's a pretty thin mandate. As development progresses, this module
  might prove itself to be too small and might get merged into another module like Main.
  """

  use TransSiberianRailroad.Aggregator
  use TypedStruct
  alias TransSiberianRailroad.Messages
  alias TransSiberianRailroad.Metadata
  alias TransSiberianRailroad.Player

  typedstruct do
    field :last_version, non_neg_integer()
    field :players, [Player.t()], default: []
  end

  #########################################################
  # CONSTRUCTORS
  #########################################################

  @impl true
  def init(), do: %__MODULE__{}

  #########################################################
  # REDUCERS (command handlers)
  #########################################################

  defp handle_command(projection, "add_player", payload) do
    %{player_name: player_name} = payload
    player_id = length(projection.players) + 1
    metadata = Metadata.from_aggregator(projection)

    if player_id <= 5 do
      Messages.player_added(player_id, player_name, metadata)
    else
      Messages.player_rejected(
        "'#{player_name}' cannot join the game. There are already 5 players.",
        metadata
      )
    end
  end

  #########################################################
  # REDUCERS (event handlers)
  #########################################################

  defp handle_event(projection, "player_added", payload) do
    %{player_id: player_id, player_name: player_name} = payload
    new_player = Player.new(player_id, player_name)
    new_players = [new_player | projection.players]
    %__MODULE__{projection | players: new_players}
  end

  # TODO extract a new event
  defp handle_event(projection, "money_transferred", payload) do
    new_players =
      for %Player{} = player <- projection.players do
        money = payload.transfers[player.id] + player.money
        %Player{player | money: money}
      end

    %__MODULE__{projection | players: new_players}
  end

  # TODO the fallback should only match on events whose names are not handled by this module.
  # In other words, I want to force a failuse if I fat-finder a payload key.

  #########################################################
  # REDUCERS
  #########################################################

  @impl true
  # TODO extract this to Metadata module or other
  def put_version(projection, sequence_number) do
    %__MODULE__{projection | last_version: sequence_number}
  end

  #########################################################
  # CONVERTERS
  #########################################################

  def count(%__MODULE__{players: players}), do: length(players)

  @spec to_list(t()) :: [Player.t()]
  def to_list(projection), do: projection.players

  #########################################################
  # HELPERS
  #########################################################

  def player_order_once_around_the_table(player_order, start_player) do
    player_count = length(player_order)

    player_order
    |> Stream.cycle()
    |> Stream.drop_while(&(&1 != start_player))
    |> Enum.take(player_count)
  end
end
