defmodule TsrWeb.MapLayout.LocationCoords do
  @moduledoc """
  Cartesian coordinates for the center of each city and external location on the map.
  """

  def get(scale) do
    Map.new(raw(), fn {l, {x, y}} ->
      {l, {round(x * scale), round(y * scale)}}
    end)
  end

  def moscow(scale) do
    get(scale) |> Map.fetch!("moscow")
  end

  def internal(scale) do
    Enum.flat_map(get(scale), fn
      {"ext_" <> _, _c} -> []
      {"moscow", _c} -> []
      {_, c} -> [c]
    end)
  end

  def external(scale) do
    get(scale)
    |> Enum.flat_map(fn {l, c} ->
      if String.starts_with?(l, "ext_"), do: [c], else: []
    end)
  end

  defp raw() do
    %{
      "ext_stpetersburg1" => {1647, 1182},
      "ext_stpetersburg2" => {1590, 1455},
      "ext_stpetersburg3" => {2080, 966},
      "ext_smolensk" => {1150, 2118},
      "smolensk" => {1508, 1880},
      "stpetersburg" => {2176, 1328},
      "ext_bryansk" => {1062, 2334},
      "bryansk" => {1460, 2296},
      "ext_oryol" => {1200, 2540},
      "moscow" => {2068, 2120},
      "rostovnadonu" => {1000, 2916},
      "belomorsk" => {2876, 1196},
      "konosha" => {2804, 1528},
      "oryol" => {1824, 2632},
      "tuapse" => {640, 3152},
      "voronezh" => {1800, 2896},
      "yaroslavl" => {2616, 2284},
      "vologda" => {2928, 1872},
      "valogda" => {2936, 1872},
      "volgograd" => {1080, 3352},
      "arkhangelsk" => {3232, 1432},
      "murmansk" => {3432, 864},
      "saratov" => {1980, 3028},
      "ext_tuapse" => {618, 3597},
      "kotlas" => {3264, 1680},
      "astrakhan" => {1452, 3420},
      "nizhnynovgorod" => {2724, 2712},
      "kazan" => {2508, 3044},
      "kirov" => {3224, 2312},
      "ext_rostovnadonu" => {1095, 3849},
      "samara" => {2312, 3308},
      "ext_astrakhan" => {1434, 3843},
      "pechora" => {3872, 1964},
      "orenburg" => {2396, 3660},
      "chelyabinsk" => {2916, 3552},
      "vorkuta" => {4232, 2084},
      "orsk" => {2680, 3904},
      "yekaterinburg" => {3344, 3576},
      "ext_orsk" => {2814, 4149},
      "salekhard" => {4384, 2452},
      "tyumen" => {3816, 3632},
      "nadym" => {4544, 2760},
      "surgut" => {4608, 3080},
      "novyurengoy" => {5008, 2752},
      "omsk" => {4104, 3984},
      "nizhnevartovsk" => {5056, 3320},
      "novosibirsk" => {5036, 4480},
      "ext_barnaul" => {4506, 5022},
      "lesosibirsk" => {5584, 3804},
      "barnaul" => {5032, 4828},
      "krasnoyarsk" => {5652, 4388},
      "ustilimsk" => {6060, 3916},
      "abakan" => {5508, 4856},
      "ustkut" => {6672, 3964},
      "bratsk" => {6384, 4432},
      "irkutsk" => {6524, 5040},
      "nizhneangarsk" => {6976, 4496},
      "ulanude" => {6940, 5076},
      "nizhnybestyakh" => {8308, 2624},
      "chita" => {7316, 4900},
      "tommot" => {8100, 3464},
      "tynda" => {8236, 3964},
      "never" => {8240, 4468},
      "ext_chita" => {7926, 5151},
      "urgal" => {8812, 4188},
      "birobidzhan" => {9004, 4616},
      "komsololsknaamure" => {9580, 4312},
      "khabarovsk" => {9508, 4728},
      "vladivostok" => {9726, 5084},
      "ext_vladivostok" => {9726, 5721}
    }
  end
end
