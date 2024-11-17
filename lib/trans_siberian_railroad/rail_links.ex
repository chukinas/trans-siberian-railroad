defmodule TransSiberianRailroad.RailLinks do
  @moduledoc """
  Defines the map of locations and rail links.
  """

  alias TransSiberianRailroad.RailLink

  @type rail_link() :: [String.t(), ...]

  @type t() :: [RailLink.t(), ...]
  @raw [
         # Moscow (starting links, CCW from Peter)
         {3, ~w(moscow stpetersburg)},
         {2, ~w(moscow smolensk)},
         {2, ~w(moscow bryansk)},
         {2, ~w(moscow oryol)},
         {2, ~w(moscow voronezh)},
         {3, ~w(moscow saratov)},
         {3, ~w(moscow samara)},
         {3, ~w(moscow kazan)},
         {3, ~w(moscow nizhnynovgorod)},
         {3, ~w(moscow yaroslavl)},
         # External Links, going CCW from Peter
         {3, ~w(stpetersburg ext_stpetersburg1)},
         {3, ~w(stpetersburg ext_stpetersburg2)},
         {3, ~w(stpetersburg ext_stpetersburg3)},
         {4, ~w(smolensk ext_smolensk)},
         {4, ~w(bryansk ext_bryansk)},
         {3, ~w(oryol ext_oryol)},
         {3, ~w(tuapse ext_tuapse)},
         {5, ~w(tuapse rostovnadonu ext_rostovnadonu)},
         {4, ~w(astrakhan ext_astrakhan)},
         {4, ~w(orsk ext_orsk)},
         {5, ~w(barnaul ext_barnaul)},
         {5, ~w(chita ext_chita)},
         {6, ~w(vladivostok ext_vladivostok)},
         # Kotlas and beyond
         {2, ~w(kotlas konosha)},
         {2, ~w(kotlas pechora)},
         {3, ~w(vorkuta pechora)},
         {3, ~w(vorkuta salekhard)},
         # Surgut and beyond
         {2, ~w(surgut tyumen)},
         {3, ~w(surgut nizhnevartovsk)},
         {3, ~w(surgut novyurengoy)},
         {3, ~w(nadym novyurengoy)},
         # West of Omsk
         {3, ~w(stpetersburg belomorsk)},
         {3, ~w(stpetersburg vologda)},
         {2, ~w(bryansk oryol)},
         {3, ~w(murmansk belomorsk)},
         {2, ~w(arkhangelsk belomorsk)},
         {2, ~w(arkhangelsk konosha)},
         {2, ~w(valogda konosha)},
         {2, ~w(valogda yaroslavl)},
         {2, ~w(kirov yaroslavl)},
         {2, ~w(kirov nizhnynovgorod)},
         {2, ~w(voronezh oryol)},
         {3, ~w(voronezh rostovnadonu)},
         {2, ~w(volgograd rostovnadonu)},
         {2, ~w(volgograd voronezh)},
         {2, ~w(volgograd astrakhan)},
         {2, ~w(samara orenburg)},
         {3, ~w(samara chelyabinsk)},
         {2, ~w(orsk orenburg)},
         {4, ~w(orsk saratov astrakhan)},
         {2, ~w(orsk chelyabinsk)},
         {3, ~w(yekaterinburg kirov)},
         {3, ~w(yekaterinburg kazan)},
         {2, ~w(yekaterinburg chelyabinsk)},
         {4, ~w(yekaterinburg chelyabinsk omsk)},
         {2, ~w(yekaterinburg tyumen)},
         {2, ~w(omsk tyumen)},
         # East of Omsk
         {3, ~w(omsk novosibirsk)},
         {3, ~w(omsk barnaul)},
         {3, ~w(abakan barnaul)},
         {3, ~w(krasnoyarsk novosibirsk)},
         {2, ~w(krasnoyarsk lesosibirsk)},
         {5, ~w(krasnoyarsk abakan bratsk irkutsk)},
         {2, ~w(ustkut ustilimsk)},
         {3, ~w(ustkut bratsk)},
         {3, ~w(ustkut nizhneangarsk)},
         {3, ~w(ulanude irkutsk)},
         {3, ~w(ulanude chita)},
         {4, ~w(nizhnybestyakh tommot)},
         {4, ~w(tynda tommot)},
         {4, ~w(tynda nizhneangarsk)},
         {3, ~w(tynda never)},
         {4, ~w(tynda urgal)},
         {3, ~w(khabarovsk komsololsknaamure)},
         {4, ~w(khabarovsk birobidzhan)},
         {4, ~w(khabarovsk vladivostok)},
         {3, ~w(never chita)},
         {4, ~w(never birobidzhan)},
         {3, ~w(urgal birobidzhan)},
         {3, ~w(urgal komsololsknaamure)}
       ]
       |> Enum.map(fn {income, rail_link} -> {income, Enum.sort(rail_link)} end)

  @rail_link_incomes Map.new(@raw, fn {income, rail_link} -> {rail_link, income} end)

  def new() do
    Enum.with_index(@raw, fn {income, linked_locations}, index ->
      RailLink.new(index, linked_locations, income)
    end)
  end

  def connected_to(city) when is_binary(city) do
    links =
      Enum.flat_map(@raw, fn {_income, rail_link} ->
        if city in rail_link, do: [rail_link], else: []
      end)

    if Enum.empty?(links) do
      require Logger
      Logger.warning("there are no links connected to #{city}")
    end

    Enum.sort(links)
  end

  def fetch_rail_link_income(rail_link) do
    case Map.fetch(@rail_link_incomes, rail_link) do
      {:ok, income} -> {:ok, income}
      :error -> {:error, "invalid rail link"}
    end
  end
end
