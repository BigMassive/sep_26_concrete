defmodule ConcreteRuntime.NodeSupervisor do
  @moduledoc """
  Working-node task tree (vaults, identity process). Not the lab supervisor.

  Lab stand-in — rewrite as seL4 later. No NIFs.
  SRK-wrapped activity list on disk is later; do not build.
  """
  use DynamicSupervisor

  def start_link(opts) do
    DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  def start_child(spec) do
    case Process.whereis(__MODULE__) do
      nil -> {:error, :node_supervisor_not_started}
      _ -> DynamicSupervisor.start_child(__MODULE__, spec)
    end
  end

  def on_power_off do
    ConcreteRuntime.Session.clear()
    terminate_all()
  end

  def on_power_on do
    if ConcreteRuntime.Bootstrap.genesis_complete?() do
      ConcreteRuntime.IdentityProcess.ensure_started()
    end

    :ok
  end

  def terminate_all do
    case Process.whereis(__MODULE__) do
      nil ->
        :ok

      pid ->
        pid
        |> DynamicSupervisor.which_children()
        |> Enum.each(fn
          {_, child, _, _} when is_pid(child) ->
            DynamicSupervisor.terminate_child(__MODULE__, child)

          _ ->
            :ok
        end)
    end
  end
end
