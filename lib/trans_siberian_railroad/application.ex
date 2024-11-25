defmodule Tsr.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      TsrWeb.Telemetry,
      {DNSCluster, query: Application.get_env(:tsr, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Tsr.PubSub},
      # Start a worker by calling: Tsr.Worker.start_link(arg)
      # {Tsr.Worker, arg},
      # Start to serve requests, typically the last entry
      TsrWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Tsr.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    TsrWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
