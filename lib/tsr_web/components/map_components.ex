defmodule TsrWeb.MapComponents do
  use TsrWeb, :html
  alias TsrWeb.GameState
  alias TsrWeb.MapLayout

  @map_layout MapLayout.new(0.02)

  @main_colors %{
    background: "fill-stone-400",
    landmass: "fill-stone-300",
    landmass_stroke: "stroke-stone-700"
  }

  @unclaimed_colors %{
    stroke_light: "stroke-stone-500",
    fill_light: "fill-stone-500",
    fill_locs: "fill-stone-600",
    fill_pips: "fill-stone-300"
  }

  @company_colors %{
    red: %{
      fill_light: "fill-rose-400",
      stroke_light: "stroke-rose-400",
      stroke_dark: "stroke-red-900"
    },
    green: %{
      fill_light: "fill-green-500",
      stroke_light: "stroke-green-500",
      stroke_dark: "stroke-green-900"
    },
    blue: %{
      fill_light: "fill-blue-400",
      stroke_light: "stroke-blue-400",
      stroke_dark: "stroke-blue-950"
    },
    yellow: %{
      fill_light: "fill-yellow-400",
      stroke_light: "stroke-yellow-400",
      stroke_dark: "stroke-yellow-800"
    },
    black: %{
      fill_light: "fill-slate-700",
      stroke_light: "stroke-slate-700",
      stroke_dark: "stroke-zinc-950"
    },
    white: %{
      fill_light: "fill-white",
      stroke_light: "stroke-white",
      stroke_dark: "stroke-indigo-300"
    }
  }

  attr :rest, :global
  attr :game_state, GameState, required: true
  attr :latest_rail_link, :list, default: []

  def map(assigns) do
    assigns =
      assign(assigns,
        dot_size: 0.75,
        main_colors: @main_colors,
        map_layout: @map_layout,
        company_colors: @company_colors,
        unclaimed_colors: @unclaimed_colors
      )

    ~H"""
    <svg viewBox={@map_layout.viewbox} xmlns="http://www.w3.org/2000/svg" {@rest}>
      <defs>
        <g id="moscow">
          <circle r="2.25" class={["stroke-stone-300", "stroke-[1.2px]"]} />
          <circle r="2.25" class={["fill-stone-300", "stroke-stone-700", "stroke-[0.6px]"]} />
          <text text-anchor="middle" y="0.5" class="font-serif text-xs stroke-stone-700 fill-stone-700" transform="translate(0 0.95) scale(0.25)">
            М
          </text>
        </g>
      </defs>
      <!-- ------------------------------------------------------- -->
      <!-- RUSSIAN LANDMASS -->
      <!-- ------------------------------------------------------- -->
      <polygon
        class={"#{@main_colors.landmass} #{@main_colors.landmass_stroke} stroke-[0.8px] md:stroke-[0.5px]"}
        stroke-linejoin="bevel"
        points={@map_layout.landmass_coords}
      />
      <!-- ------------------------------------------------------- -->
      <!-- TITLE -->
      <!-- ------------------------------------------------------- -->
      <text
        text-anchor="middle"
        class={"font-serif #{@main_colors.background} #{@main_colors.landmass_stroke} stroke-[0.8px] text-xs"}
        transform="translate(150 55) scale(0.9) rotate(-25) "
      >
        Trans-Siberian Railroad
      </text>
      <text
        text-anchor="middle"
        class={"font-serif #{@main_colors.background} text-xs"}
        transform="translate(150 55) scale(0.9) rotate(-25) "
      >
        Trans-Siberian Railroad
      </text>
      <!-- ------------------------------------------------------- -->
      <!-- RAIL LINKS & INCOME DICE -->
      <!-- ------------------------------------------------------- -->
      <g :for={rail_link_id <- MapLayout.rail_link_ids()} id={"rail-link-#{rail_link_id}"}>
        <g id={"rail-link-segments-#{rail_link_id}"}>
          <line
            :for={segment <- MapLayout.segments(@map_layout, @game_state, rail_link_id)}
            :if={segment.owner != :unclaimed}
            x1={segment.x1}
            y1={segment.y1}
            x2={segment.x2}
            y2={segment.y2}
            stroke-linecap="round"
            class={"stroke-[1.4px] md:stroke-[1px] #{@company_colors[segment.owner].stroke_dark}"}
          />
          <line
            :for={segment <- MapLayout.segments(@map_layout, @game_state, rail_link_id)}
            :if={segment.owner != :unclaimed}
            x1={segment.x1}
            y1={segment.y1}
            x2={segment.x2}
            y2={segment.y2}
            stroke-linecap="round"
            class={"stroke-[0.8px]  md:stroke-[0.4px] #{@company_colors[segment.owner].stroke_light}"}
          />
          <line
            :for={segment <- MapLayout.segments(@map_layout, @game_state, rail_link_id)}
            :if={segment.owner == :unclaimed}
            x1={segment.x1}
            y1={segment.y1}
            x2={segment.x2}
            y2={segment.y2}
            stroke-linecap="round"
            class={"stroke-[0.4px] #{@unclaimed_colors.stroke_light}"}
          />
        </g>
        <% die = MapLayout.income_die(@map_layout, @game_state, rail_link_id) %>
        <.rail_link_pips
          id={"rail-link-die-#{rail_link_id}"}
          x={die.x}
          y={die.y}
          dot_size={@dot_size}
          pip_count={die.income}
          class={if die.claimed, do: "animate-fade opacity-0"}
        />
      </g>
      <!-- ------------------------------------------------------- -->
      <!-- MOSCOW -->
      <!-- ------------------------------------------------------- -->
      <use xlink:href="#moscow" x={@map_layout.moscow_xy.x} y={@map_layout.moscow_xy.y} />
      <!-- ------------------------------------------------------- -->
      <!-- INTERNAL & EXTERNAL LOCATIONS -->
      <!-- ------------------------------------------------------- -->
      <.location
        :for={location_name <- MapLayout.location_names()}
        location_name={location_name}
        dot_size={@dot_size}
        map_layout={@map_layout}
        game_state={@game_state}
      />
    </svg>
    """
  end

  attr :dot_size, :any, required: true
  attr :map_layout, MapLayout, required: true
  attr :game_state, GameState, required: true
  attr :location_name, :string, required: true

  defp location(assigns) do
    location_name = assigns.location_name
    owner = GameState.location_owner!(assigns.game_state, location_name)

    {x, y} = MapLayout.location_coord!(assigns.map_layout, location_name)

    unclaimed? = owner == :unclaimed

    assigns = assign(assigns, x: x, y: y, unclaimed: unclaimed?, location_name: location_name)

    assigns =
      assign(
        assigns,
        if unclaimed? do
          [r: assigns.dot_size, class: @unclaimed_colors.fill_locs]
        else
          class = [
            "stroke-[0.4px]",
            @company_colors[owner][:fill_light],
            @company_colors[owner][:stroke_dark]
          ]

          [r: assigns.dot_size * 1.4, class: class]
        end
      )

    ~H"""
    <circle id={"location-#{@location_name}"} r={@r} cx={@x} cy={@y} class={@class} />
    """
  end

  # Only have pip_count?
  attr :x, :integer
  attr :y, :integer
  attr :pip_count, :integer, required: true
  attr :dot_size, :any
  attr :rest, :global

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

    assigns = assign(assigns, pip_coords: pip_coords, dice_size: 2, color: @unclaimed_colors)

    ~H"""
    <g {@rest}>
      <rect
        x={@x - @dice_size / 2}
        y={@y - @dice_size / 2}
        width={@dice_size}
        height={@dice_size}
        class={@color.fill_light}
        rx="0.2"
      />
      <circle :for={{x, y} <- @pip_coords} r={@dot_size / 3} cx={x} cy={y} class={@color.fill_pips} />
    </g>
    """
  end
end
