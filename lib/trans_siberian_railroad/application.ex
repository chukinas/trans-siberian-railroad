defmodule TransSiberianRailroad.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      TransSiberianRailroadWeb.Telemetry,
      {DNSCluster, query: Application.get_env(:trans_siberian_railroad, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: TransSiberianRailroad.PubSub},
      # Start a worker by calling: TransSiberianRailroad.Worker.start_link(arg)
      # {TransSiberianRailroad.Worker, arg},
      # Start to serve requests, typically the last entry
      TransSiberianRailroadWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: TransSiberianRailroad.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    TransSiberianRailroadWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
