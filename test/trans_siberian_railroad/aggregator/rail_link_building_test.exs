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
    # What's the general flow here?
    # - RailLinks handles the command
    # - If the rail link is invalid, RailLinks issues a "rail_link_rejected" event. Fields: player, company, rail_link, reason.
    # - Otherwise, RailLinks issues a "rail_link_sequence_begun" event. Fields: player, company, rail_link, ref_id
    # - PlayerTurn handles "rail_link_sequence_begun".
    #   - PlayerTurn issues a "player_action_reserved" if valid. Fields: player, ref_id
    #     PlayerTurn puts the action "on hold"
    #   - PlayerTurn issues a "player_action_rejected" if invalid. Fields: player, ref_id, reason
    # - StockCertificates handles "rail_link_sequence_begun"
    #   - StockCertificates issues "stock_certificates_begun" if valid. Fields: player, company, ref_id
    #     It puts the rail_link "on hold"
    #   - StockCertificates issues "stock_certificates_rejected" if valid. Fields: player, company, ref_id, reason
    # - Money handles "rail_link_sequence_begun"
    #   - Money issues "money_set_aside" if valid. Fields: company, amount, ref_id
    #     Money puts that company's money amount "on hold"
    #   - Money issues "money_rejected" if invalid. Fields: company, amount, ref_id, reason
    # - RailLinks handles all the above events.
    #   - If there were rejections, it issues a "rail_link_rejected" event. Fields: player, company, rail_link, reason
    #     The resources (player turn action, money, rail link) are released.
    #   - Otherwise, issue "rail_link_built" event
    #     The resources are committed.
    #     PlayerTurn

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

      assert event.payload == %{
               player: any_player,
               company: "red",
               rail_link: @invalid_rail_link,
               reason: "not a player turn"
             }
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

      assert event.payload == %{
               player: wrong_player,
               company: "red",
               rail_link: @invalid_rail_link,
               reason: "incorrect player"
             }
    end

    # StockCertificates
    test "player does not have controlling share in company"
    # StockCertificates
    test "company not public (it's private or nationalized)"
    # Money
    test "insufficient funds"
    # RailLinks
    test "rail link not connected to existing network"
    test "invalid rail link"
  end
end
