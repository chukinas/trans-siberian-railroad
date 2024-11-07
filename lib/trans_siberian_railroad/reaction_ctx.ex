defmodule TransSiberianRailroad.ReactionCtx do
  def if_uuid_unsent(reaction_ctx, event_id, fun) do
    if MapSet.member?(reaction_ctx.sent_ids, event_id) do
      nil
    else
      fun.()
    end
  end
end
