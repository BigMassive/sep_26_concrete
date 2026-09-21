defmodule ConcreteRuntime.Session do
  @moduledoc """
  One seated login on this node. Esc (Godot unsit) does not clear this.
  Exit session drops this user's vault use. OTP still trusts `principal_id`
  on HTTP — not signed sessions (ADR 0008 stage 5 later).
  """
  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def current do
    case Process.whereis(__MODULE__) do
      nil -> %{logged_in: false, principal_id: nil, username: nil, abw: nil}
      _ -> GenServer.call(__MODULE__, :current)
    end
  end

  def put(principal, abw) when is_map(principal) and is_map(abw) do
    GenServer.call(__MODULE__, {:put, principal, abw})
  end

  def clear do
    case Process.whereis(__MODULE__) do
      nil -> :ok
      _ -> GenServer.call(__MODULE__, :clear)
    end
  end

  def abw(principal_id) when is_binary(principal_id) do
    cur = current()

    if cur.logged_in and cur.principal_id == principal_id do
      cur.abw
    else
      nil
    end
  end

  def logged_in?(principal_id) when is_binary(principal_id) do
    cur = current()
    cur.logged_in and cur.principal_id == principal_id
  end

  @impl true
  def init(_opts) do
    {:ok, empty()}
  end

  @impl true
  def handle_call(:current, _from, state), do: {:reply, state, state}

  def handle_call({:put, principal, abw}, _from, _state) do
    state = %{
      logged_in: true,
      principal_id: principal.id,
      username: principal.display_name,
      abw: abw,
      note: "not signed HTTP — OTP trusts principal_id until ADR 0008-5"
    }

    {:reply, {:ok, state}, state}
  end

  def handle_call(:clear, _from, state) do
    if is_binary(state.principal_id) do
      ConcreteRuntime.Vault.drop_use(state.principal_id)
    end

    {:reply, :ok, empty()}
  end

  defp empty do
    %{
      logged_in: false,
      principal_id: nil,
      username: nil,
      abw: nil,
      note: "not signed HTTP — OTP trusts principal_id until ADR 0008-5"
    }
  end
end
