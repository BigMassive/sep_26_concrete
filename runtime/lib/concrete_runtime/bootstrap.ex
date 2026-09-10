defmodule ConcreteRuntime.Bootstrap do
  @moduledoc """
  First working node + first user bootstrap (ADR 0005 / 0008).

  On a fresh data dir, onboards King via the user-identity sidecar (index-0
  ML-DSA-87 public key is the principal id) and mints the bootstrap
  (do-anything) capability to that key. Lab supervisor is not the holder.
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
        case new_principal(display_name, king?: false) do
          {:ok, principal} ->
            state = %{state | principals: state.principals ++ [principal]}
            persist!(path, state)
            {:reply, {:ok, principal}, %{s | state: state}}

          {:error, _} = err ->
            {:reply, err, s}
        end

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
      |> maybe_upgrade_legacy_ids(path)
    else
      state = fresh_bootstrap!()
      persist!(path, state)
      state
    end
  end

  defp fresh_bootstrap! do
    node_id = "node-1"
    {:ok, king} = new_principal("King", king?: true)
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

  defp maybe_upgrade_legacy_ids(state, path) do
    if Enum.any?(state.principals, &(not String.starts_with?(&1.id, "mldsa87:"))) do
      upgraded =
        Enum.map(state.principals, fn p ->
          if String.starts_with?(p.id, "mldsa87:") do
            p
          else
            case new_principal(p.display_name, king?: p.role == "king") do
              {:ok, n} -> %{n | role: p.role, created_at: p.created_at}
              {:error, reason} -> raise "ADR 0008 onboard failed for #{p.display_name}: #{inspect(reason)}"
            end
          end
        end)

      old_to_new =
        state.principals
        |> Enum.zip(upgraded)
        |> Map.new(fn {old, new} -> {old.id, new.id} end)

      king = Enum.find(upgraded, &(&1.role == "king"))

      state = %{
        state
        | principals: upgraded,
          bootstrap_holders: Enum.map(state.bootstrap_holders, &Map.get(old_to_new, &1, &1)),
          bootstrap_capability: %{
            state.bootstrap_capability
            | holder_principal_id: king.id
          }
      }

      persist!(path, state)
      state
    else
      state
    end
  end

  defp new_principal(display_name, king?: king?) do
    case ConcreteRuntime.UserIdentity.onboard(display_name) do
      {:ok, %{id: id, public_key: pk}} ->
        {:ok,
         %{
           id: id,
           public_key: pk,
           display_name: display_name,
           role: if(king?, do: "king", else: "user"),
           created_at: DateTime.utc_now() |> DateTime.to_iso8601()
         }}

      {:error, _} = err ->
        err
    end
  end

  defp public_status(state) do
    king = Enum.find(state.principals, &(&1.role == "king"))

    %{
      harness_note: "OTP node ground truth — not Godot; supervisor is not the cap holder",
      node_id: state.node_id,
      created_at: state.created_at,
      king: king && Map.take(king, [:id, :display_name, :role, :public_key]),
      bootstrap_capability: state.bootstrap_capability,
      principals:
        Enum.map(state.principals, fn p ->
          Map.put(
            Map.take(p, [:id, :display_name, :role, :public_key]),
            :has_bootstrap_capability,
            p.id in state.bootstrap_holders
          )
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
            "public_key" => Map.get(p, :public_key, p.id),
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
            public_key: p["public_key"] || p["id"],
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
