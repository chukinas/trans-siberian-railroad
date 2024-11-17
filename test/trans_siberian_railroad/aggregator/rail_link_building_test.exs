defmodule TransSiberianRailroad.Aggregator.RailLinkBuildingTest do
  # This module exists to test the "build_rail_link" and "build_two_rail_links" commands.
  # It's a domain complicated enough to warrant its own test module.
  # This module does not test the "build_initial_rail_link" command, which is tested in the AuctionTest module.

  use ExUnit.Case, async: true
  import TransSiberianRailroad.CommandFactory
  import TransSiberianRailroad.GameHelpers
  import TransSiberianRailroad.GameTestHelpers

  taggable_setups()
  @moduletag :start_game
  @moduletag :random_first_auction_phase

  # NOTE: we have not yet implemented the concept of "jumping",
  # where a company pays another company to use its network.
  describe "build_rail_link -> rail_link_rejected when" do
    @invalid_rail_link ~w(A1 A2)

    test "a build_rail_link is already being bearbeitet"
    @tag random_first_auction_phase: false
    test "not a player turn", context do
      # GIVEN start game and in-progress auction phase
      game = context.game
      # WHEN player attempts to build a rail link
      any_player = rand_player(game)
      game = build_rail_link(any_player, "red", @invalid_rail_link) |> injest_commands(game)
      # THEN player_action_rejected and (as a result) rail_link_rejected are issued
      assert event = get_one_event(game, "player_action_rejected")
      assert event.payload == %{player: any_player, reason: "not a player turn"}
      assert get_one_event(game, "rail_link_rejected")
      assert event = get_one_event(game, "rail_link_rejected")

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
      game = build_rail_link(wrong_player, "red", @invalid_rail_link) |> injest_commands(game)
      # THEN player_action_rejected and (as a result) rail_link_rejected are issued
      assert event = get_one_event(game, "player_action_rejected")
      assert event.payload == %{player: wrong_player, reason: "incorrect player"}
      assert event = get_one_event(game, "rail_link_rejected")

      assert %{
               player: ^wrong_player,
               company: "red",
               rail_link: @invalid_rail_link,
               reasons: reasons
             } = event.payload

      assert "incorrect player" in reasons
    end

    # StockCertificates
    test "company not public (it's private or nationalized)", context do
      # GIVEN completed first auction phase
      game = context.game
      # WHEN player attempts to build a rail link for a private company
      # (There's a slight chance that all companies were passed on, in which case this random/1 will fail. Maybe fix later.)
      event = filter_events(game, "player_won_company_auction") |> Enum.random()
      %{auction_winner: player, company: company} = event.payload
      game = build_rail_link(player, company, @invalid_rail_link) |> injest_commands(game)
      # THEN
      assert event = get_one_event(game, "company_is_not_public")
      assert event.payload == %{company: company}
      assert event = get_one_event(game, "rail_link_rejected")

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
           %{company: "red", player: 1, amount: 8},
           %{company: "blue"},
           %{company: "green"},
           %{company: "yellow"}
         ]
    test "player does not have controlling share in company", context do
      # GIVEN completed first auction phase
      game = context.game

      game =
        [
          purchase_single_stock(1, "red", 8),
          purchase_single_stock(2, "red", 8),
          # Player 1 now has controlling share in Red
          pass(3),
          pass(1)
        ]
        |> injest_commands(game)

      # WHEN player 2 (whose does not have controlling share in Red) attempts to build a rail link
      game =
        build_rail_link(2, "red", @invalid_rail_link)
        |> injest_commands(game)

      # THEN the attempt is rejected
      assert event = get_one_event(game, "rail_link_rejected")

      assert %{
               player: 2,
               company: "red",
               rail_link: @invalid_rail_link,
               reasons: reasons
             } = event.payload

      assert "player does not have controlling share in company" in reasons
    end

    # Money
    test "insufficient funds"
    # RailLinks
    test "rail link not connected to existing network"
    test "invalid rail link"

    @tag random_first_auction_phase: false
    test "another link is already being built", context do
      # GIVEN completed first auction phase
      game = context.game
      # WHEN player attempts to build a rail link for a private company
      game =
        [
          build_rail_link(1, "red", @invalid_rail_link),
          build_rail_link(2, "blue", @invalid_rail_link)
        ]
        |> injest_commands(game, one_by_one: false)

      # THEN
      assert [_, event] = filter_events(game, "rail_link_rejected")

      assert %{
               player: 2,
               company: "blue",
               rail_link: @invalid_rail_link,
               reasons: reasons
             } = event.payload

      assert "another rail link is already being built" in reasons
    end
  end
end
