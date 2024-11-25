defmodule TsrWeb.MapComponents do
  use TsrWeb, :html
  alias TsrWeb.Map

  @map_layout Map.new(0.02)

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
        map_layout: @map_layout
      )

    ~H"""
    <svg viewBox={@map_layout.viewbox} xmlns="http://www.w3.org/2000/svg" {@rest}>
      <defs>
        <circle id="int_loc" r={@dot_size} class="fill-yellow-900" />
        <g id="moscow">
          <circle r="2.25" class="fill-yellow-900" />
          <circle r="1.5" class={@color.landmass} />
          <circle r={@dot_size} class="fill-yellow-900" />
        </g>
        <g id="ext_loc">
          <circle r="1.5" class="fill-yellow-900" />
          <circle r={@dot_size} class="fill-lime-100" />
        </g>
      </defs>
      <polygon
        class={"#{@color.landmass} stroke-yellow-800 stroke-[1px] md:stroke-[0.5px]"}
        stroke-linejoin="bevel"
        points={@map_layout.landmass_coords}
      />
      <%= for {x1, y1, x2, y2} <- @map_layout.rail_link_segments do %>
        <line
          stroke-dasharray="2 .35"
          class="stroke-[0.4px] stroke-yellow-600"
          x1={x1}
          y1={y1}
          x2={x2}
          y2={y2}
        />
      <% end %>
      <%= for {x, y} <- @map_layout.internal_location_coords do %>
        <use xlink:href="#int_loc" x={x} y={y} />
      <% end %>
      <%= for {x, y} <- @map_layout.external_location_coords do %>
        <use xlink:href="#ext_loc" x={x} y={y} />
      <% end %>
      <use xlink:href="#moscow" x={@map_layout.moscow_xy.x} y={@map_layout.moscow_xy.y} />
      <%= for {x, y, income} <- Map.income_dice(@map_layout) do %>
        <.rail_link_pips x={x} y={y} dot_size={@dot_size} pip_count={income} />
      <% end %>
    </svg>
    """
  end

  attr :x, :integer, required: true
  attr :y, :integer, required: true
  attr :pip_count, :integer, required: true
  attr :dot_size, :any, required: true

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
end
