defmodule ConcreteRuntime.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    children =
      if Application.get_env(:concrete_runtime, :start_runtime, true) do
        data_dir =
          System.get_env("CONCRETE_DATA_DIR") ||
            Path.expand("../../../lab/data/node", __DIR__)

        File.mkdir_p!(data_dir)

        port = String.to_integer(System.get_env("CONCRETE_HTTP_PORT") || "4000")

        [
          {ConcreteRuntime.Bootstrap, data_dir: data_dir},
          {Bandit, plug: ConcreteRuntime.API, scheme: :http, port: port}
        ]
      else
        []
      end

    opts = [strategy: :one_for_one, name: ConcreteRuntime.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
