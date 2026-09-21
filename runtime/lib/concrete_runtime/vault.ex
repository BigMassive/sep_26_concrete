defmodule ConcreteRuntime.Vault do
  @moduledoc """
  Per-user volatile key holder on this node.

  Lab stand-in — rewrite as seL4 later. No NIFs.

  Product rule is in-system use-not-see. Paper/bank (genesis and login import
  fields) may show human-readable keys; this process does not persist them
  and does not export the private material.
  """
  use GenServer

  def via(principal_id), do: {:via, Registry, {ConcreteRuntime.VaultRegistry, principal_id}}

  def start_link(opts) do
    principal_id = Keyword.fetch!(opts, :principal_id)
    GenServer.start_link(__MODULE__, opts, name: via(principal_id))
  end

  @doc "Start this principal's vault under the node supervisor if needed."
  def ensure(principal_id) when is_binary(principal_id) do
    case lookup(principal_id) do
      {:ok, pid} ->
        {:ok, pid}

      :error ->
        spec = {__MODULE__, principal_id: principal_id}

        case ConcreteRuntime.NodeSupervisor.start_child(spec) do
          {:ok, pid} -> {:ok, pid}
          {:error, {:already_started, pid}} -> {:ok, pid}
          {:error, _} = err -> err
        end
    end
  end

  def import_private_key(principal_id, private_key)
      when is_binary(principal_id) and is_binary(private_key) do
    with {:ok, pid} <- require_pid(principal_id) do
      GenServer.call(pid, {:import, principal_id, private_key})
    end
  end

  def ensure_import(principal_id, private_key)
      when is_binary(principal_id) and is_binary(private_key) do
    with {:ok, _} <- ensure(principal_id) do
      import_private_key(principal_id, private_key)
    end
  end

  def grant_use(principal_id) when is_binary(principal_id) do
    with {:ok, pid} <- require_pid(principal_id) do
      GenServer.call(pid, {:grant_use, principal_id})
    end
  end

  def drop_use(principal_id) when is_binary(principal_id) do
    case lookup(principal_id) do
      {:ok, pid} -> GenServer.call(pid, {:drop_use, principal_id})
      :error -> :ok
    end
  end

  def usable?(principal_id) when is_binary(principal_id) do
    case lookup(principal_id) do
      {:ok, pid} -> GenServer.call(pid, :usable?)
      :error -> false
    end
  end

  def has_material?(principal_id) when is_binary(principal_id) do
    case lookup(principal_id) do
      {:ok, pid} -> GenServer.call(pid, :has_material?)
      :error -> false
    end
  end

  def require_usable(principal_id) when is_binary(principal_id) do
    if usable?(principal_id), do: :ok, else: {:error, :vault_unusable}
  end

  def status(principal_id) when is_binary(principal_id) do
    case lookup(principal_id) do
      {:ok, pid} -> GenServer.call(pid, :status)
      :error -> %{running: false, in_use: false, has_material: false}
    end
  end

  defp lookup(principal_id) do
    case Registry.lookup(ConcreteRuntime.VaultRegistry, principal_id) do
      [{pid, _}] -> {:ok, pid}
      [] -> :error
    end
  rescue
    ArgumentError -> :error
  end

  defp require_pid(principal_id) do
    case lookup(principal_id) do
      {:ok, pid} -> {:ok, pid}
      :error -> {:error, :vault_not_started}
    end
  end

  @impl true
  def init(opts) do
    principal_id = Keyword.fetch!(opts, :principal_id)

    {:ok,
     %{
       principal_id: principal_id,
       private_key: nil,
       in_use: false
     }}
  end

  @impl true
  def handle_call({:import, caller, private_key}, _from, state) do
    cond do
      caller != state.principal_id ->
        {:reply, {:error, :use_vault_denied}, state}

      not is_binary(private_key) or String.trim(private_key) == "" ->
        {:reply, {:error, :missing_private_key}, state}

      true ->
        {:reply, :ok, %{state | private_key: private_key, in_use: true}}
    end
  end

  def handle_call({:grant_use, caller}, _from, state) do
    if caller == state.principal_id and is_binary(state.private_key) do
      {:reply, :ok, %{state | in_use: true}}
    else
      {:reply, {:error, :use_vault_denied}, state}
    end
  end

  def handle_call({:drop_use, caller}, _from, state) do
    if caller == state.principal_id do
      {:reply, :ok, %{state | in_use: false}}
    else
      {:reply, {:error, :use_vault_denied}, state}
    end
  end

  def handle_call(:usable?, _from, state) do
    {:reply, state.in_use and is_binary(state.private_key), state}
  end

  def handle_call(:has_material?, _from, state) do
    {:reply, is_binary(state.private_key), state}
  end

  def handle_call(:status, _from, state) do
    {:reply,
     %{
       running: true,
       in_use: state.in_use,
       has_material: is_binary(state.private_key),
       principal_id: state.principal_id
     }, state}
  end
end
