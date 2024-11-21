defmodule TransSiberianRailroad.Aggregator.RailLinkBuildingTest do
  # This module exists to test the "build_internal_rail_link" and "build_two_rail_links" commands.
  # It's a domain complicated enough to warrant its own test module.
  # This module does not test the "build_initial_rail_link" command, which is tested in the AuctionTest module.

  use TransSiberianRailroad.Case, async: true
  @moduletag :start_game
  @moduletag :random_first_auction_phase

  # NOTE: we have not yet implemented the concept of "jumping",
  # where a company pays another company to use its network.
  describe "build_internal_rail_link -> external_rail_link_rejected when" do
    @invalid_rail_link ~w(A1 A2)

    @tag random_first_auction_phase: false
    test "not a player turn", context do
      # GIVEN start game and in-progress auction phase
      game = context.game
      # WHEN player attempts to build a rail link
      any_player = rand_player(game)

      game =
        build_internal_rail_link(any_player, "red", @invalid_rail_link) |> injest_commands(game)

      # THEN player_action_rejected and (as a result) internal_rail_link_rejected are issued
      assert event = get_one_event(game, "player_action_rejected")
      assert event.payload == %{player: any_player, reason: "not a player turn"}
      assert get_one_event(game, "internal_rail_link_rejected")
      assert event = get_one_event(game, "internal_rail_link_rejected")

      assert %{
               player: ^any_player,
               company: "red",
               rail_link: @invalid_rail_link,
               reasons: reasons
             } = event.payload

      assert "not a player turn" in reasons
    end

    test "wrong player", context do
      # GIVEN completed first auction phase
      game = context.game
      # WHEN wrong player attempts to build a rail link
      wrong_player = wrong_player(game)

      game =
        build_internal_rail_link(wrong_player, "red", @invalid_rail_link)
        |> injest_commands(game)

      # THEN player_action_rejected and (as a result) internal_rail_link_rejected are issued
      assert event = get_one_event(game, "player_action_rejected")
      assert event.payload == %{player: wrong_player, reason: "incorrect player"}
      assert event = get_one_event(game, "internal_rail_link_rejected")

      assert %{
               player: ^wrong_player,
               company: "red",
               rail_link: @invalid_rail_link,
               reasons: reasons
             } = event.payload

      assert "incorrect player" in reasons
    end

    test "company not public (it's private or nationalized)", context do
      # GIVEN completed first auction phase
      game = context.game
      # WHEN player attempts to build a rail link for a private company
      # (There's a slight chance that all companies were passed on, in which case this random/1 will fail. Maybe fix later.)
      event = filter_events(game, "player_won_company_auction") |> Enum.random()
      %{player: player, company: company} = event.payload

      game =
        build_internal_rail_link(player, company, @invalid_rail_link) |> injest_commands(game)

      # THEN
      assert event = get_one_event(game, "internal_rail_link_rejected")

      assert %{
               player: ^player,
               company: ^company,
               rail_link: @invalid_rail_link,
               reasons: reasons
             } = event.payload

      assert "company is not public" in reasons
    end

    @tag :simple_setup
    @tag rig_auctions: [
           %{company: "red", player: 1, rubles: 8},
           %{company: "blue"},
           %{company: "green"},
           %{company: "yellow"}
         ]
    test "player does not have controlling share in company", context do
      # GIVEN completed first auction phase
      game = context.game
      # AND player 1 has controlling share in Red,
      game =
        [
          purchase_single_stock(1, "red", 8),
          purchase_single_stock(2, "red", 8),
          pass(3),
          pass(1)
        ]
        |> injest_commands(game)

      # WHEN player 2 (whose does not have controlling share in Red) attempts to build a rail link
      game =
        build_internal_rail_link(2, "red", @invalid_rail_link)
        |> injest_commands(game)

      # THEN the attempt is rejected
      assert event = get_one_event(game, "internal_rail_link_rejected")

      assert %{
               player: 2,
               company: "red",
               rail_link: @invalid_rail_link,
               reasons: reasons
             } = event.payload

      assert "player does not have controlling share in company" in reasons
    end

    @moscow_links [
      ["bryansk", "moscow"],
      #
      ["kazan", "moscow"],
      ["moscow", "nizhnynovgorod"],
      ["moscow", "oryol"],
      ["moscow", "samara"],
      ["moscow", "saratov"],
      ["moscow", "smolensk"],
      #
      ["moscow", "stpetersburg"],
      ["moscow", "voronezh"],
      ["moscow", "yaroslavl"]
    ]

    @tag :simple_setup
    @tag rig_auctions: [
           %{company: "red", player: 1, rubles: 8, rail_link: List.first(@moscow_links)},
           %{company: "blue"},
           %{company: "green"},
           %{company: "yellow"}
         ]
    test "company has insufficient funds", context do
      # GIVEN all players have controlling share in "red"
      game = context.game

      game =
        [
          pass(1),
          purchase_single_stock(2, "red", 8),
          purchase_single_stock(3, "red", 8),
          # all three players now have controlling share and the company has 24 rubles
          # so we can build 6 links before running out of rubles
          build_internal_rail_link(1, "red", Enum.at(@moscow_links, 1)),
          build_internal_rail_link(2, "red", Enum.at(@moscow_links, 2)),
          build_internal_rail_link(3, "red", Enum.at(@moscow_links, 3)),
          build_internal_rail_link(1, "red", Enum.at(@moscow_links, 4)),
          build_internal_rail_link(2, "red", Enum.at(@moscow_links, 5)),
          build_internal_rail_link(3, "red", Enum.at(@moscow_links, 6))
        ]
        |> injest_commands(game)

      # WHEN a player now attempts to build a rail link
      rail_link = Enum.at(@moscow_links, 7)
      game = build_internal_rail_link(1, "red", rail_link) |> injest_commands(game)
      # THEN the attempt is rejected

      assert event = get_one_event(game, "internal_rail_link_rejected")

      assert %{
               player: 1,
               company: "red",
               rail_link: ^rail_link,
               reasons: reasons
             } = event.payload

      assert "company has insufficient funds" in reasons
    end

    @tag :simple_setup
    @tag rig_auctions: [
           %{company: "red", player: 1, rubles: 8},
           %{company: "blue"},
           %{company: "green"},
           %{company: "yellow"}
         ]
    test "rail link not connected to existing network", context do
      # GIVEN player 1 has controlling share in "red"
      game = context.game

      # WHEN player 1 attempts to build a non-existent rail link
      unconnected_rail_link = ~w/kotlas pechora/
      game = build_internal_rail_link(1, "red", unconnected_rail_link) |> injest_commands(game)
      # THEN the attempt is rejected
      assert event = get_one_event(game, "internal_rail_link_rejected")

      assert %{
               player: 1,
               company: "red",
               rail_link: ^unconnected_rail_link,
               reasons: reasons
             } = event.payload

      assert "rail link not connected to company's built rail links" in reasons
    end

    @tag :simple_setup
    @tag rig_auctions: [
           %{company: "red", player: 1, rubles: 8},
           %{company: "blue"},
           %{company: "green"},
           %{company: "yellow"}
         ]
    test "rail link does not exist", context do
      # GIVEN player 1 has controlling share in "red"
      game = context.game

      # WHEN player 1 attempts to build a non-existent rail link
      game = build_internal_rail_link(1, "red", @invalid_rail_link) |> injest_commands(game)
      # THEN the attempt is rejected
      assert event = get_one_event(game, "internal_rail_link_rejected")

      assert %{
               player: 1,
               company: "red",
               rail_link: @invalid_rail_link,
               reasons: reasons
             } = event.payload

      assert "invalid rail link" in reasons
    end

    @tag :simple_setup
    @tag rig_auctions: [
           %{company: "red", player: 1, rubles: 8},
           %{company: "blue"},
           %{company: "green"},
           %{company: "yellow"}
         ]
    test "rail link has already been built", context do
      # GIVEN player 1 has controlling share in "red"
      game = context.game

      # WHEN player 1 attempts to build red's initial rail link
      initial_rail_link =
        with event = get_one_event(game, "initial_rail_link_built"), do: event.payload.rail_link

      game = build_internal_rail_link(1, "red", initial_rail_link) |> injest_commands(game)

      # THEN the attempt is rejected
      assert event = get_one_event(game, "internal_rail_link_rejected")

      assert %{
               player: 1,
               company: "red",
               rail_link: ^initial_rail_link,
               reasons: reasons
             } = event.payload

      assert "rail link already built" in reasons
    end

    @tag random_first_auction_phase: false
    test "another link is already being built", context do
      # GIVEN completed first auction phase
      game = context.game
      # WHEN player attempts to build a rail link for a private company
      game =
        [
          build_internal_rail_link(1, "red", @invalid_rail_link),
          build_internal_rail_link(2, "blue", @invalid_rail_link)
        ]
        |> injest_commands(game, one_by_one: false)

      # THEN
      assert [_, event] = filter_events(game, "internal_rail_link_rejected")

      assert %{
               player: 2,
               company: "blue",
               rail_link: @invalid_rail_link,
               reasons: reasons
             } = event.payload

      assert "another rail link is already being built" in reasons
    end
  end

  describe "internal_rail_link_built" do
    test "increases the income for the railroad"
  end
end
