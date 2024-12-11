defmodule TsrWeb.MapComponents do
  use TsrWeb, :html
  alias TsrWeb.MapLayout

  @map_layout MapLayout.new(0.02)

  attr :rest, :global

  def map(assigns) do
    color = %{
      background: "fill-lime-100",
      landmass: "fill-yellow-500",
      dot: "fill-yellow-900"
    }

    assigns =
      assign(assigns,
        dot_size: 0.75,
        color: color,
        map_layout: @map_layout,
        game_state: TsrWeb.GameState.new(),
        stroke_colors: [
          unclaimed: "stroke-yellow-600",
          red: "stroke-red-600",
          blue: "stroke-blue-600",
          green: "stroke-green-700",
          yellow: "stroke-amber-700",
          black: "stroke-zinc-600",
          white: "stroke-stone-300"
        ],
        fill_colors: [
          unclaimed: "fill-yellow-900",
          red: "fill-red-900",
          blue: "fill-blue-900",
          green: "fill-green-900",
          yellow: "fill-amber-900",
          black: "fill-zinc-950",
          white: "fill-stone-500"
        ]
      )

    ~H"""
    <svg viewBox={@map_layout.viewbox} xmlns="http://www.w3.org/2000/svg" {@rest}>
      <defs>
        <g id="moscow">
          <circle r="2.25" class="fill-yellow-900" />
          <circle r="1.5" class={@color.landmass} />
          <circle r={@dot_size} class="fill-yellow-900" />
        </g>
        for pip_count
        <- 1..6 do <circle id="pip-#{pip_count}" r={@dot_size / 3} class="fill-yellow-950" /> end
      </defs>
      <polygon
        class={"#{@color.landmass} stroke-yellow-800 stroke-[1px] md:stroke-[0.5px]"}
        stroke-linejoin="bevel"
        points={@map_layout.landmass_coords}
      />
      <%= for {owner, class} <- @stroke_colors do %>
        <g
          stroke-dasharray={if owner == :unclaimed, do: "2 .35"}
          class={
            if owner == :unclaimed, do: "stroke-[0.4px] #{class}", else: "stroke-[0.6px] #{class}"
          }
        >
          <%= for {x1, y1, x2, y2} <- MapLayout.segments(@map_layout, @game_state, owner) do %>
            <line x1={x1} y1={y1} x2={x2} y2={y2} />
          <% end %>
        </g>
      <% end %>

      <%= for {owner, class} <- @fill_colors do %>
        <% r = if owner == :unclaimed, do: @dot_size, else: @dot_size * 1.4 %>
        <%= for {x, y} <- MapLayout.int_loc_coords(@map_layout, @game_state, owner) do %>
          <circle id="blarg" r={r} cx={x} cy={y} class={class} />
        <% end %>
      <% end %>

      <%= for {owner, class} <- @stroke_colors do %>
        <%= stroke = if owner == :unclaimed, do: "stroke-[0.6px]", else: "stroke-[0.8px]" %>
        <%= for {x, y} <- MapLayout.ext_loc_coords(@map_layout, @game_state, owner) do %>
          <circle r="1.3" cx={x} cy={y} class={"fill-lime-100 #{stroke} #{class} drop-shadow-sm"} />
        <% end %>
      <% end %>

      <use xlink:href="#moscow" x={@map_layout.moscow_xy.x} y={@map_layout.moscow_xy.y} />
      <%= for {x, y, income} <- MapLayout.income_dice(@map_layout, @game_state) do %>
        <.rail_link_pips x={x} y={y} dot_size={@dot_size} pip_count={income} />
      <% end %>
    </svg>
    """
  end

  # Only have pip_count?
  attr :x, :integer
  attr :y, :integer
  attr :pip_count, :integer, required: true
  attr :dot_size, :any

  def rail_link_pips(assigns) do
    scale = 0.5

    pip_coords =
      case assigns.pip_count do
        1 -> [{0, 0}]
        2 -> [{-1, -1}, {1, 1}]
        3 -> [{-1, 1}, {0, 0}, {1, -1}]
        4 -> [{-1, -1}, {1, -1}, {-1, 1}, {1, 1}]
        5 -> [{-1, -1}, {1, -1}, {0, 0}, {-1, 1}, {1, 1}]
        6 -> [{-1, -1}, {1, -1}, {-1, 0}, {1, 0}, {-1, 1}, {1, 1}]
      end
      |> Enum.map(fn {x, y} -> {x * scale + assigns[:x], y * scale + assigns[:y]} end)

    assigns = assign(assigns, pip_coords: pip_coords, dice_size: 2)

    ~H"""
    <rect
      x={@x - @dice_size / 2}
      y={@y - @dice_size / 2}
      width={@dice_size}
      height={@dice_size}
      class="fill-yellow-600"
      rx="0.2"
    />
    <%= for {x, y} <- @pip_coords do %>
      <circle r={@dot_size / 3} cx={x} cy={y} class="fill-yellow-950" />
    <% end %>
    """
  end

  attr :pip_count, :integer, required: true
  attr :dot_size, :any

  def rail_link_pip_def(assigns) do
    scale = 0.5

    pip_coords =
      case assigns.pip_count do
        1 -> [{0, 0}]
        2 -> [{-1, -1}, {1, 1}]
        3 -> [{-1, 1}, {0, 0}, {1, -1}]
        4 -> [{-1, -1}, {1, -1}, {-1, 1}, {1, 1}]
        5 -> [{-1, -1}, {1, -1}, {0, 0}, {-1, 1}, {1, 1}]
        6 -> [{-1, -1}, {1, -1}, {-1, 0}, {1, 0}, {-1, 1}, {1, 1}]
      end
      |> Enum.map(fn {x, y} -> {x * scale + assigns[:x], y * scale + assigns[:y]} end)

    assigns = assign(assigns, pip_coords: pip_coords, dice_size: 2)

    ~H"""
    <g id={"income-die-#{@pip_count}"}>
      <rect width={@dice_size} height={@dice_size} class="fill-yellow-600" rx="0.2" />
      <%= for {x, y} <- @pip_coords do %>
        <circle r={@dot_size / 3} cx={x} cy={y} class="fill-yellow-950" />
      <% end %>
    </g>
    """
  end
end
