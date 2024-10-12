alias TransSiberianRailroad.Projection
alias TransSiberianRailroad.Aggregator.{Auction, Players}
import TransSiberianRailroad.Messages
metadata = [sequence_number: 1]
auction = &Projection.orange(Auction, &1)
