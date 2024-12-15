defmodule TsrWeb.GameLive do
  use TsrWeb, :live_view
  alias TsrWeb.GameState

  def render(assigns) do
    ~H"""
    <div class="w-full h-screen font-semibold flex flex-col gap-y-4">
      <div class="grow basis-3 md:basis-1"></div>
      <TsrWeb.MapComponents.map class="mx-4 sm:mx-auto max-w-7xl" game_state={@game_state} />
      <div class="mx-auto max-w-xl px-4 sm:px-6 lg:px-8 text-sm text-stone-800">
        <p>
          Welcome to my work-in-progress passion project,
          an Elixir/Phoenix/LiveView implementation of the <b>Trans-Siberian Railroad</b>
          board game, designed by Tom Russell.
          Visit the publisher, <a
            href=" https://www.riograndegames.com/games/trans-siberian-railroad/"
            target="_blank"
            class="font-bold hover:underline hover:text-yellow-700"
          >
        Rio Grande Games
      </a>,
          or view it out on <a
            href="https://boardgamegeek.com/boardgame/180205/trans-siberian-railroad"
            target="_blank"
            class="font-bold hover:underline hover:text-yellow-700"
          >
        BoardGameGeek
      </a>.
        </p>
      </div>
      <div class="grow basis-20"></div>
    </div>
    """
  end

  def mount(_params, _session, socket) do
    if connected?(socket), do: :timer.send_interval(500, self(), :tick)

    {:ok,
     assign(socket,
       turns: turns(),
       game_state: GameState.new(),
       count: 0
     )}
  end

  def handle_info(:tick, socket) do
    turns = socket.assigns.turns
    game_state = socket.assigns.game_state

    {turns, owner, maybe_rail_link} = next_turns_and_rail_link(turns, game_state)

    game_state =
      if maybe_rail_link do
        GameState.add_rail_link(game_state, owner, maybe_rail_link)
      else
        game_state
      end

    {:noreply,
     assign(socket,
       count: socket.assigns.count + 1,
       turns: turns,
       game_state: game_state,
       latest_rail_link: maybe_rail_link || []
     )}
  end

  defp next_turns_and_rail_link(turns, game_state) do
    # Eventually, this match fails and the live view restarts. This is intentional.
    [owner | turns] = turns

    if rail_link = GameState.get_rand_rail_link(game_state, owner) do
      {turns, owner, rail_link}
    else
      next_turns_and_rail_link(turns, game_state)
    end
  end

  defp turns() do
    Stream.cycle([:black, :white, :red, :blue, :green, :yellow])
    |> Stream.take(200)
    |> Enum.to_list()
  end
end
