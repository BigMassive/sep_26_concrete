defmodule ConcreteRuntime.IdentityProcess do
  @moduledoc """
  King-started child: username + PIN. Stub α/β/ω that pass granted caps.

  This is not ML-DSA session binding (ADR 0008 stage 5 later).

  Lab stand-in — rewrite as seL4 later. No NIFs.
  """
  use GenServer

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def ensure_started do
    case Process.whereis(__MODULE__) do
      nil ->
        ConcreteRuntime.NodeSupervisor.start_child({__MODULE__, []})

      pid when is_pid(pid) ->
        {:ok, pid}
    end
  end

  def running? do
    is_pid(Process.whereis(__MODULE__))
  end

  def verify(username, pin) when is_binary(username) and is_binary(pin) do
    case Process.whereis(__MODULE__) do
      nil -> {:error, :identity_process_not_started}
      _ -> GenServer.call(__MODULE__, {:verify, username, pin})
    end
  end

  def passing_abw do
    %{alpha: 1, beta: 1, omega: 1}
  end

  @impl true
  def init(_opts) do
    {:ok, %{note: "stub αβω — not signed sessions"}}
  end

  @impl true
  def handle_call({:verify, username, pin}, _from, state) do
    reply =
      with {:ok, pair} <- ConcreteRuntime.DataObjects.lookup_username(username),
           :ok <- ConcreteRuntime.DataObjects.member_d1(pair.public_key),
           :ok <- ConcreteRuntime.DataObjects.check_pin(pair.public_key, pin) do
        {:ok, %{id: pair.public_key, display_name: username, public_key: pair.public_key}}
      end

    {:reply, reply, state}
  end
end
