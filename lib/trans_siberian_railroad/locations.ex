defmodule TransSiberianRailroad.Locations do
  @moduledoc """
  Build all the locations needed by the game.
  """

  alias TransSiberianRailroad.Location

  def new() do
    [
      "Abakan",
      "Arkhangelsk",
      "Astrakhan",
      "Barnaul",
      "Belomorsk",
      "Birobidzhan",
      "Bratsk",
      "Bryansk",
      "Chelyabinsk",
      "Chita",
      {"ext_astrakhan", "Astrakhan External Link"},
      {"ext_barnaul", "Barnaul External Link"},
      {"ext_bryansk", "Bryansk External Link"},
      {"ext_chita", "Chita External Link"},
      {"ext_orsk", "Orsk External Link"},
      {"ext_oryol", "Oryol External Link"},
      {"ext_rostovnadonu", "Rostov-Na-Donu External Link"},
      {"ext_smolensk", "Smolensk External Link"},
      {"ext_stpetersburg1", "St. Petersburg External Link #1"},
      {"ext_stpetersburg2", "St. Petersburg External Link #2"},
      {"ext_stpetersburg3", "St. Petersburg External Link #3"},
      {"ext_tuapse", "Rostov-Na-Donu/Tuapse External Link"},
      {"ext_vladivostok", "Vladivostok External Link"},
      "Irkutsk",
      "Kazan",
      "Khabarovsk",
      "Kirov",
      "Komsololsk-Na-Amure",
      "Konosha",
      "Kotlas",
      "Krasnoyarsk",
      "Lesosibirsk",
      "Moscow",
      "Murmansk",
      "Nadym",
      "Never",
      "Nizhneangarsk",
      "Nizhnevartovsk",
      "Nizhny Bestyakh",
      "Nizhny Novgorod",
      "Novosibirsk",
      "Novy Urengoy",
      "Omsk",
      "Orenburg",
      "Orsk",
      "Oryol",
      "Pechora",
      "Rostov-Na-Donu",
      "Salekhard",
      "Samara",
      "Saratov",
      "Smolensk",
      "St. Petersburg",
      "Surgut",
      "Tommot",
      "Tuapse",
      "Tynda",
      "Tyumen",
      "Ulan-Ude",
      "Urgal",
      "Ust-Ilimsk",
      "Ust Kut",
      "Valogda",
      "Vladivostok",
      "Volgograd",
      "Vologda",
      "Vorkuta",
      "Voronezh",
      "Yaroslavl",
      "Yekaterinburg"
    ]
    |> Enum.map(fn
      name when is_binary(name) ->
        id =
          String.downcase(name)
          |> String.replace(["-", " ", "."], "")

        Location.new(id, name)

      {id, name} ->
        Location.new(id, name)
    end)
  end
end
