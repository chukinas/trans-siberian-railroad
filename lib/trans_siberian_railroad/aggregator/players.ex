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

  #########################################################
  # PROJECTION
  #########################################################

  use TransSiberianRailroad.Projection

  typedstruct do
    version_field()
    field :players, [Player.t()], default: []
  end

  handle_event "money_transferred", ctx do
    new_players =
      for %Player{} = player <- ctx.projection.players do
        case ctx.payload.transfers[player.id] do
          nil ->
            player

          amount ->
            money = amount + player.money
            %Player{player | money: money}
        end
      end

    [players: new_players]
  end

  handle_event "player_added", ctx do
    %{player_id: player_id, player_name: player_name} = ctx.payload
    new_player = Player.new(player_id, player_name)
    new_players = [new_player | ctx.projection.players]
    [players: new_players]
  end

  #########################################################
  # REDUCERS (command handlers)
  #########################################################

  handle_command "add_player", ctx do
    %{player_name: player_name} = ctx.payload
    projection = ctx.projection
    player_id = length(projection.players) + 1
    metadata = Metadata.from_aggregator(projection)

    if player_id <= 5 do
      Messages.player_added(player_id, player_name, metadata)
    else
      Messages.player_rejected(
        player_name,
        "There are already 5 players",
        metadata
      )
    end
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
