defmodule ConcreteRuntime.Bootstrap do
  @moduledoc """
  First working node + first user bootstrap (ADR 0005).

  On a fresh data dir, mints the bootstrap (do-anything) capability to the King
  principal. Lab supervisor is not the capability holder — the user is.
  """
  use GenServer

  @bootstrap_meaning "bootstrap/do-anything"

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def status, do: GenServer.call(__MODULE__, :status)

  def ensure_principal(display_name) when is_binary(display_name) do
    GenServer.call(__MODULE__, {:ensure_principal, display_name})
  end

  @doc """
  Fail-closed capability check for the slice mutate path.
  For beat 1+, holding the bootstrap capability covers any action.
  """
  def authorize(principal_id, _action) when is_binary(principal_id) do
    GenServer.call(__MODULE__, {:authorize, principal_id})
  end

  @impl true
  def init(opts) do
    data_dir = Keyword.fetch!(opts, :data_dir)
    path = Path.join(data_dir, "bootstrap.json")
    state = load_or_bootstrap(path)
    {:ok, %{path: path, state: state}}
  end

  @impl true
  def handle_call(:status, _from, %{state: state} = s) do
    {:reply, public_status(state), s}
  end

  def handle_call({:ensure_principal, display_name}, _from, %{state: state, path: path} = s) do
    case Enum.find(state.principals, &(&1.display_name == display_name)) do
      nil ->
        principal = new_principal(display_name, king?: false)
        state = %{state | principals: state.principals ++ [principal]}
        persist!(path, state)
        {:reply, {:ok, principal}, %{s | state: state}}

      existing ->
        {:reply, {:ok, existing}, s}
    end
  end

  def handle_call({:authorize, principal_id}, _from, %{state: state} = s) do
    reply =
      if principal_id in state.bootstrap_holders do
        {:ok, :allowed, @bootstrap_meaning}
      else
        {:error, :capability_denied}
      end

    {:reply, reply, s}
  end

  defp load_or_bootstrap(path) do
    if File.exists?(path) do
      path
      |> File.read!()
      |> Jason.decode!()
      |> from_json()
    else
      state = fresh_bootstrap()
      persist!(path, state)
      state
    end
  end

  defp fresh_bootstrap do
    node_id = "node-1"
    king = new_principal("King", king?: true)
    cap_id = "cap-bootstrap-#{short_id()}"

    %{
      node_id: node_id,
      created_at: DateTime.utc_now() |> DateTime.to_iso8601(),
      principals: [king],
      bootstrap_capability: %{
        id: cap_id,
        meaning: @bootstrap_meaning,
        holder_principal_id: king.id
      },
      bootstrap_holders: [king.id]
    }
  end

  defp new_principal(display_name, king?: king?) do
    %{
      id: "principal-#{short_id()}",
      display_name: display_name,
      role: if(king?, do: "king", else: "user"),
      created_at: DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end

  defp public_status(state) do
    king = Enum.find(state.principals, &(&1.role == "king"))

    %{
      harness_note: "OTP node ground truth — not Godot; supervisor is not the cap holder",
      node_id: state.node_id,
      created_at: state.created_at,
      king: king && Map.take(king, [:id, :display_name, :role]),
      bootstrap_capability: state.bootstrap_capability,
      principals:
        Enum.map(state.principals, fn p ->
          Map.put(Map.take(p, [:id, :display_name, :role]), :has_bootstrap_capability, p.id in state.bootstrap_holders)
        end)
    }
  end

  defp persist!(path, state) do
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, Jason.encode!(to_json(state), pretty: true))
  end

  defp to_json(state) do
    %{
      "node_id" => state.node_id,
      "created_at" => state.created_at,
      "principals" =>
        Enum.map(state.principals, fn p ->
          %{
            "id" => p.id,
            "display_name" => p.display_name,
            "role" => p.role,
            "created_at" => p.created_at
          }
        end),
      "bootstrap_capability" => %{
        "id" => state.bootstrap_capability.id,
        "meaning" => state.bootstrap_capability.meaning,
        "holder_principal_id" => state.bootstrap_capability.holder_principal_id
      },
      "bootstrap_holders" => state.bootstrap_holders
    }
  end

  defp from_json(map) do
    %{
      node_id: map["node_id"],
      created_at: map["created_at"],
      principals:
        Enum.map(map["principals"], fn p ->
          %{
            id: p["id"],
            display_name: p["display_name"],
            role: p["role"],
            created_at: p["created_at"]
          }
        end),
      bootstrap_capability: %{
        id: map["bootstrap_capability"]["id"],
        meaning: map["bootstrap_capability"]["meaning"],
        holder_principal_id: map["bootstrap_capability"]["holder_principal_id"]
      },
      bootstrap_holders: map["bootstrap_holders"]
    }
  end

  defp short_id do
    :crypto.strong_rand_bytes(6) |> Base.url_encode64(padding: false)
  end
end
