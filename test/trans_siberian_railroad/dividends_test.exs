defmodule TransSiberianRailroad.DividendsTest do
  use TransSiberianRailroad.Case, async: true

  @moduletag :simple_setup
  @moduletag :start_game
  @moduletag :random_first_auction_phase

  describe "dividends" do
    @tag rig_auctions: [
           %{company: "red", player: 1, amount: 8},
           %{company: "blue"},
           %{company: "green"},
           %{company: "yellow"}
         ]
    test "are paid after passing five times", context do
      # GIVEN players have passed 4 times
      game = context.game

      game =
        [
          pass(1),
          pass(2),
          pass(3),
          pass(1)
        ]
        |> injest_commands(game)

      # AND we haven't yet paid out dividends
      refute get_latest_event(game, "dividends_paid")
      # WHEN the next player passes
      game = pass(2) |> injest_commands(game)
      # THEN we see a dividends_paid event
      assert get_latest_event(game, "dividends_paid")
    end

    test "the certificate value is always rounded up (and make sure we test various stock counts too)"
    test "money actually gets transferred"

    @tag rig_auctions: [
           %{company: "red", player: 1, amount: 8},
           %{company: "blue", player: 2, amount: 8},
           %{company: "green"},
           %{company: "yellow"}
         ]
    test "are paid out by operating companies (both private and public)", context do
      # GIVEN red and blue are auctioned off, but not green and yellow
      game = context.game
      # AND a red stock certificate is purchased,
      # making "red" a public company and leaving "blue" a private company
      # AND four players have take the "pass" action
      game =
        [
          purchase_single_stock(2, "red", 8),
          pass(3),
          pass(1),
          pass(2),
          pass(3)
        ]
        |> injest_commands(game)

      # WHEN we pass one more time
      game = pass(1) |> injest_commands(game)

      # THEN we see two company_dividends_paid events
      assert [_, _] = events = filter_events(game, "company_dividends_paid")

      # AND the red company pays out 1 or 2 rubles per share
      assert red_event = Enum.find(events, &(&1.payload.company == "red"))
      assert map_size(red_event.payload) == 6

      assert %{
               company: "red",
               company_income: company_income,
               stock_count: 2,
               player_payouts: [
                 %{player: 1, rubles: red_certificate_value},
                 %{player: 2, rubles: red_certificate_value}
               ],
               certificate_value: red_certificate_value,
               command_id: _
             } = red_event.payload

      # All the moscow rail links are worth either 2 or 3, so this should always succeed:
      case company_income do
        2 -> assert red_certificate_value == 1
        3 -> assert red_certificate_value == 2
      end

      # AND the blue company pays out 2 or 3 rubles per share
      assert blue_event = Enum.find(events, &(&1.payload.company == "blue"))

      assert %{
               company: "blue",
               company_income: company_income,
               stock_count: 1,
               player_payouts: [%{player: 2, rubles: blue_certificate_value}],
               certificate_value: blue_certificate_value,
               command_id: _
             } = blue_event.payload

      assert company_income in 2..3
      assert company_income == blue_certificate_value

      # AND WHEN we force a game end in order to count up players' rubles
      game = force_end_game(game)
      # THEN we see a game_end_player_money_calculated event
      assert event = get_one_event(game, "game_end_player_money_calculated")

      starting_rubles = 48
      stock_cert_cost = 8

      assert event.payload == %{
               player_money: [
                 %{
                   player: 1,
                   money: starting_rubles - stock_cert_cost + red_certificate_value
                 },
                 %{
                   player: 2,
                   money:
                     starting_rubles - 2 * stock_cert_cost + red_certificate_value +
                       blue_certificate_value
                 },
                 %{
                   player: 3,
                   money: starting_rubles
                 }
               ]
             }
    end
  end

  test "a nationalized company pays no dividends"
end
