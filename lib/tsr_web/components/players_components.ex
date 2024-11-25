defmodule TsrWeb.PlayersComponents do
  use TsrWeb, :html
  alias Tsr.RandomGame.Player
  attr :player, Player, required: true

  def player(assigns) do
    %Player{current?: current?} = assigns.player

    color =
      if current? do
        "stroke-stone-500"
      else
        "stroke-red-500"
      end

    assigns = assign(assigns, :color, color)

    ~H"""
    <Heroicons.icon name="user-circle" class={"h-6 w-6 inline #{@color}"} />
    """
  end
end
