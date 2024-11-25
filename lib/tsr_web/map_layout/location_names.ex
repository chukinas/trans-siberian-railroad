defmodule TsrWeb.BlargComponents.LocationNames do
  @moduledoc """
  Map location ids (e.g. "ext_rostovnadonu")
  to their human-readable englishs (e.g. "Rostov-Na-Donu External Link")
  """

  def get() do
    id_from_english = &(String.downcase(&1) |> String.replace(["-", " ", "."], ""))

    Enum.map(raw(), fn
      %{id: id, english: english} -> %{id: id, name: english}
      %{english: english} -> %{id: id_from_english.(english), name: english}
    end)
  end

  defp raw() do
    [
      %{english: "Abakan"},
      %{english: "Arkhangelsk"},
      %{english: "Astrakhan"},
      %{english: "Barnaul"},
      %{english: "Belomorsk"},
      %{english: "Birobidzhan"},
      %{english: "Bratsk"},
      %{english: "Bryansk"},
      %{english: "Chelyabinsk"},
      %{english: "Chita"},
      %{id: "ext_bryansk", english: "Bryansk External Link"},
      %{id: "ext_astrakhan", english: "Astrakhan External Link"},
      %{id: "ext_oryol", english: "Oryol External Link"},
      %{id: "ext_smolensk", english: "Smolensk External Link"},
      %{id: "ext_stpetersburg1", english: "St. Petersburg External Link #1"},
      %{id: "ext_stpetersburg2", english: "St. Petersburg External Link #2"},
      %{id: "ext_stpetersburg3", english: "St. Petersburg External Link #3"},
      %{id: "ext_tuapse", english: "Rostov-Na-Donu/Tuapse External Link"},
      %{id: "ext_rostovnadonu", english: "Rostov-Na-Donu External Link"},
      %{id: "ext_orsk", english: "Orsk External Link"},
      %{id: "ext_barnaul", english: "Barnaul External Link"},
      %{id: "ext_chita", english: "Chita External Link"},
      %{id: "ext_vladivostok", english: "Vladivostok External Link"},
      %{english: "Irkutsk"},
      %{english: "Kazan"},
      %{english: "Khabarovsk"},
      %{english: "Kirov"},
      %{english: "Komsololsk-Na-Amure"},
      %{english: "Konosha"},
      %{english: "Kotlas"},
      %{english: "Krasnoyarsk"},
      %{english: "Lesosibirsk"},
      %{english: "Moscow", russian: "Москва"},
      %{english: "Murmansk"},
      %{english: "Nadym"},
      %{english: "Never"},
      %{english: "Nizhneangarsk"},
      %{english: "Nizhnevartovsk"},
      %{english: "Nizhny Bestyakh"},
      %{english: "Nizhny Novgorod"},
      %{english: "Novosibirsk"},
      %{english: "Novy Urengoy"},
      %{english: "Omsk"},
      %{english: "Orenburg"},
      %{english: "Orsk"},
      %{english: "Oryol"},
      %{english: "Pechora"},
      %{english: "Rostov-Na-Donu"},
      %{english: "Salekhard"},
      %{english: "Samara"},
      %{english: "Saratov"},
      %{english: "Smolensk"},
      %{english: "St. Petersburg"},
      %{english: "Surgut"},
      %{english: "Tommot"},
      %{english: "Tuapse"},
      %{english: "Tynda"},
      %{english: "Tyumen"},
      %{english: "Ulan-Ude"},
      %{english: "Urgal"},
      %{english: "Ust-Ilimsk"},
      %{english: "Ust Kut"},
      %{english: "Valogda"},
      %{english: "Vladivostok"},
      %{english: "Volgograd"},
      %{english: "Vologda"},
      %{english: "Vorkuta"},
      %{english: "Voronezh"},
      %{english: "Yaroslavl"},
      %{english: "Yekaterinburg"}
    ]
  end
end
