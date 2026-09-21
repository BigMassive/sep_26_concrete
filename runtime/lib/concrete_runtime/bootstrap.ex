defmodule ConcreteRuntime.Bootstrap do
  @moduledoc """
  First working node + first user bootstrap (ADR 0005 / 0008 / docs/11).

  Empty CoT: no auto-King at process start. Genesis workspace is the one-shot
  mint. Replay fails unless zeroise. Lab supervisor is not the holder.

  Capability records (holder, verb/resource, α/β/ω stub, optional workspace
  pointer) live here. GraphEdit pictures cannot widen them.
  """
  use GenServer

  @bootstrap_meaning "bootstrap/do-anything"

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def status, do: GenServer.call(__MODULE__, :status)

  def genesis_complete? do
    ConcreteRuntime.Lab.genesis_complete?()
  end

  def cot_index do
    GenServer.call(__MODULE__, :cot_index)
  end

  def ensure_can_genesis do
    GenServer.call(__MODULE__, :ensure_can_genesis)
  end

  def begin_genesis(attrs) when is_map(attrs) do
    GenServer.call(__MODULE__, {:begin_genesis, attrs})
  end

  def finish_genesis(cot) when is_map(cot) do
    GenServer.call(__MODULE__, {:finish_genesis, cot})
  end

  def abort_genesis do
    GenServer.call(__MODULE__, :abort_genesis)
  end

  def reset_empty do
    GenServer.call(__MODULE__, :reset_empty)
  end

  def add_principal(actor_id, attrs) when is_binary(actor_id) and is_map(attrs) do
    GenServer.call(__MODULE__, {:add_principal, actor_id, attrs})
  end

  def grant(actor_id, cap) when is_binary(actor_id) and is_map(cap) do
    GenServer.call(__MODULE__, {:grant, actor_id, cap})
  end

  def capabilities(principal_id) when is_binary(principal_id) do
    GenServer.call(__MODULE__, {:capabilities, principal_id})
  end

  def lookup_principal(id_or_name) when is_binary(id_or_name) do
    GenServer.call(__MODULE__, {:lookup_principal, id_or_name})
  end

  def has_cap?(principal_id, verb, resource \\ "*") when is_binary(principal_id) do
    GenServer.call(__MODULE__, {:has_cap, principal_id, verb, resource})
  end

  def export_state do
    GenServer.call(__MODULE__, :export_state)
  end

  def restore_state(state) when is_map(state) do
    GenServer.call(__MODULE__, {:restore_state, state})
  end

  def remember_d5(public_key, did) when is_binary(public_key) and is_binary(did) do
    GenServer.call(__MODULE__, {:remember_d5, public_key, did})
  end

  @doc """
  Fail-closed capability check. Bootstrap covers anything. Other verbs match
  OTP records — not GraphEdit layout. Locked-graph edits are a separate deny.
  """
  def authorize(principal_id, action) when is_binary(principal_id) and is_binary(action) do
    authorize(principal_id, action, "*")
  end

  def authorize(principal_id, action, resource)
      when is_binary(principal_id) and is_binary(action) do
    GenServer.call(__MODULE__, {:authorize, principal_id, action, resource})
  end

  @impl true
  def init(opts) do
    data_dir = Keyword.fetch!(opts, :data_dir)
    path = Path.join(data_dir, "bootstrap.json")
    state = load_or_empty(path)
    ConcreteRuntime.Lab.note_genesis(state.genesis_complete == true)
    {:ok, %{path: path, state: state, snapshot: nil}}
  end

  @impl true
  def handle_call(:status, _from, %{state: state} = s) do
    {:reply, public_status(state), s}
  end

  def handle_call(:genesis_complete?, _from, %{state: state} = s) do
    {:reply, state.genesis_complete == true, s}
  end

  def handle_call(:cot_index, _from, %{state: state} = s) do
    {:reply, state.cot, s}
  end

  def handle_call(:ensure_can_genesis, _from, %{state: state} = s) do
    cond do
      not ConcreteRuntime.Lab.powered?() ->
        {:reply, {:error, :node_powered_off}, s}

      state.genesis_complete and not ConcreteRuntime.Lab.zeroised?() ->
        {:reply, {:error, :genesis_replay}, s}

      true ->
        {:reply, :ok, s}
    end
  end

  def handle_call({:begin_genesis, attrs}, _from, %{state: state, path: path} = s) do
    cond do
      not ConcreteRuntime.Lab.powered?() ->
        {:reply, {:error, :node_powered_off}, s}

      state.genesis_complete and not ConcreteRuntime.Lab.zeroised?() ->
        {:reply, {:error, :genesis_replay}, s}

      true ->
        case mint_helen(attrs) do
          {:ok, helen, cap, caps} ->
            pending = %{
              node_id: "node-1",
              created_at: now(),
              principals: [helen],
              bootstrap_capability: cap,
              bootstrap_holders: [helen.id],
              capabilities: caps,
              genesis_complete: false,
              cot: %{}
            }

            {:reply, {:ok, helen}, %{s | state: pending, snapshot: {path, state}}}

          {:error, _} = err ->
            {:reply, err, s}
        end
    end
  end

  def handle_call({:finish_genesis, cot}, _from, %{state: state, path: path} = s) do
    state = %{state | genesis_complete: true, cot: stringify_cot(cot)}
    persist!(path, state)
    ConcreteRuntime.Lab.note_genesis(true)
    {:reply, :ok, %{s | state: state, snapshot: nil}}
  end

  def handle_call(:abort_genesis, _from, %{path: path, snapshot: snap} = s) do
    state =
      case snap do
        {^path, prev} -> prev
        _ -> empty_state()
      end

    ConcreteRuntime.Lab.note_genesis(state.genesis_complete == true)
    {:reply, :ok, %{s | state: state, snapshot: nil}}
  end

  def handle_call(:reset_empty, _from, %{path: path} = s) do
    state = empty_state()
    persist!(path, state)
    ConcreteRuntime.Lab.note_genesis(false)
    {:reply, :ok, %{s | state: state, snapshot: nil}}
  end

  def handle_call({:add_principal, actor_id, attrs}, _from, %{state: state, path: path} = s) do
    with {:ok, _, _} <- do_authorize(state, actor_id, "introduce-user", "*"),
         {:ok, principal} <- build_principal(attrs, king?: false) do
      case Enum.find(
             state.principals,
             &(&1.id == principal.id or &1.display_name == principal.display_name)
           ) do
        nil ->
          state = %{state | principals: state.principals ++ [principal]}
          persist!(path, state)
          {:reply, {:ok, principal}, %{s | state: state}}

        %{id: id} = existing when id == principal.id ->
          {:reply, {:ok, existing}, %{s | state: state}}

        _ ->
          {:reply, {:error, :username_taken}, s}
      end
    else
      {:error, _} = err -> {:reply, err, s}
    end
  end

  def handle_call({:grant, actor_id, cap}, _from, %{state: state, path: path} = s) do
    with {:ok, _, _} <- do_authorize(state, actor_id, "grant", "*") do
      rec = normalize_cap(cap)
      state = %{state | capabilities: state.capabilities ++ [rec]}
      persist!(path, state)
      {:reply, {:ok, rec}, %{s | state: state}}
    else
      {:error, _} = err -> {:reply, err, s}
    end
  end

  def handle_call({:capabilities, principal_id}, _from, %{state: state} = s) do
    caps = Enum.filter(state.capabilities, &(&1.holder == principal_id))
    {:reply, caps, s}
  end

  def handle_call({:lookup_principal, id_or_name}, _from, %{state: state} = s) do
    found =
      Enum.find(state.principals, fn p ->
        p.id == id_or_name or p.display_name == id_or_name
      end)

    {:reply, found, s}
  end

  def handle_call({:authorize, principal_id, action, resource}, _from, %{state: state} = s) do
    {:reply, do_authorize(state, principal_id, action, resource), s}
  end

  def handle_call({:has_cap, principal_id, verb, resource}, _from, %{state: state} = s) do
    reply =
      principal_id in state.bootstrap_holders or
        has_matching_cap?(state, principal_id, verb, resource)

    {:reply, reply, s}
  end

  def handle_call(:export_state, _from, %{state: state} = s) do
    {:reply, state, s}
  end

  def handle_call({:restore_state, state}, _from, %{path: path} = s) do
    persist!(path, state)
    ConcreteRuntime.Lab.note_genesis(state.genesis_complete == true)
    {:reply, :ok, %{s | state: state, snapshot: nil}}
  end

  def handle_call({:remember_d5, public_key, did}, _from, %{state: state, path: path} = s) do
    d5 = Map.merge(state.cot["d5"] || %{}, %{public_key => did})
    cot = Map.put(state.cot, "d5", d5)
    state = %{state | cot: cot}
    persist!(path, state)
    {:reply, :ok, %{s | state: state}}
  end

  defp do_authorize(state, principal_id, action, resource) do
    cond do
      not is_binary(principal_id) or principal_id == "" ->
        {:error, :capability_denied}

      principal_id in state.bootstrap_holders ->
        {:ok, :allowed, @bootstrap_meaning}

      action == "mutate" ->
        {:error, :capability_denied}

      has_matching_cap?(state, principal_id, action, resource) ->
        if abw_pass?(principal_id, matching_cap(state, principal_id, action, resource)) do
          {:ok, :allowed, action}
        else
          {:error, :capability_denied}
        end

      true ->
        {:error, :capability_denied}
    end
  end

  defp has_matching_cap?(state, principal_id, action, resource) do
    Enum.any?(state.capabilities, &cap_covers?(&1, principal_id, action, resource))
  end

  defp matching_cap(state, principal_id, action, resource) do
    Enum.find(state.capabilities, &cap_covers?(&1, principal_id, action, resource))
  end

  defp cap_covers?(cap, principal_id, action, resource) do
    cap.holder == principal_id and cap.verb == action and
      (cap.resource == "*" or cap.resource == resource)
  end

  defp abw_pass?(principal_id, cap) do
    case ConcreteRuntime.Session.abw(principal_id) do
      %{alpha: a, beta: b, omega: o} ->
        a >= cap.alpha and b >= cap.beta and o >= cap.omega

      _ ->
        false
    end
  end

  defp mint_helen(attrs) do
    username = String.trim(to_string(attrs[:username] || attrs["username"] || ""))
    public_key = String.trim(to_string(attrs[:public_key] || attrs["public_key"] || ""))
    pin = String.trim(to_string(attrs[:pin] || attrs["pin"] || ""))
    private_key = to_string(attrs[:private_key] || attrs["private_key"] || "")

    cond do
      username == "" ->
        {:error, :username_required}

      not String.starts_with?(public_key, "mldsa87:") ->
        {:error, :public_key_required}

      String.trim(private_key) == "" ->
        {:error, :private_key_required}

      pin == "" ->
        {:error, :pin_required}

      true ->
        helen = %{
          id: public_key,
          public_key: public_key,
          display_name: username,
          role: "king",
          created_at: now()
        }

        cap_id = "cap-bootstrap-#{short_id()}"

        cap = %{
          id: cap_id,
          meaning: @bootstrap_meaning,
          holder_principal_id: helen.id,
          holder: helen.id,
          verb: "bootstrap",
          resource: "*",
          alpha: 0,
          beta: 0,
          omega: 0,
          workspace_cid: nil
        }

        home = normalize_cap(%{holder: helen.id, verb: "home", resource: "*"})
        {:ok, helen, cap, [cap, home]}
    end
  end

  defp build_principal(attrs, king?: king?) do
    username =
      String.trim(
        to_string(
          attrs[:username] || attrs["username"] || attrs[:display_name] || attrs["display_name"] ||
            ""
        )
      )

    public_key = String.trim(to_string(attrs[:public_key] || attrs["public_key"] || ""))

    cond do
      username == "" ->
        {:error, :username_required}

      not String.starts_with?(public_key, "mldsa87:") ->
        {:error, :public_key_required}

      true ->
        {:ok,
         %{
           id: public_key,
           public_key: public_key,
           display_name: username,
           role: if(king?, do: "king", else: "user"),
           created_at: now()
         }}
    end
  end

  defp normalize_cap(cap) do
    holder = cap[:holder] || cap["holder"]
    verb = cap[:verb] || cap["verb"]
    resource = cap[:resource] || cap["resource"] || "*"

    %{
      id: cap[:id] || cap["id"] || "cap-#{verb}-#{short_id()}",
      holder: holder,
      verb: verb,
      resource: resource,
      alpha: cap[:alpha] || cap["alpha"] || 0,
      beta: cap[:beta] || cap["beta"] || 0,
      omega: cap[:omega] || cap["omega"] || 0,
      workspace_cid: cap[:workspace_cid] || cap["workspace_cid"],
      meaning: cap[:meaning] || cap["meaning"] || verb
    }
  end

  defp stringify_cot(cot) do
    cot
    |> Enum.map(fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), v}
      {k, v} -> {k, v}
    end)
    |> Map.new()
  end

  defp load_or_empty(path) do
    if File.exists?(path) do
      path
      |> File.read!()
      |> Jason.decode!()
      |> from_json()
    else
      empty_state()
    end
  end

  defp empty_state do
    %{
      node_id: "node-1",
      created_at: now(),
      principals: [],
      bootstrap_capability: nil,
      bootstrap_holders: [],
      capabilities: [],
      genesis_complete: false,
      cot: %{}
    }
  end

  defp public_status(state) do
    king = Enum.find(state.principals, &(&1.role == "king"))

    %{
      harness_note: "OTP node ground truth — not Godot; supervisor is not the cap holder",
      node_id: state.node_id,
      created_at: state.created_at,
      genesis_complete: state.genesis_complete,
      king: king && Map.take(king, [:id, :display_name, :role, :public_key]),
      bootstrap_capability: state.bootstrap_capability,
      cot: state.cot,
      principals:
        Enum.map(state.principals, fn p ->
          Map.put(
            Map.take(p, [:id, :display_name, :role, :public_key]),
            :has_bootstrap_capability,
            p.id in state.bootstrap_holders
          )
        end),
      capabilities: state.capabilities
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
      "genesis_complete" => state.genesis_complete,
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
      "bootstrap_capability" =>
        case state.bootstrap_capability do
          nil ->
            nil

          cap ->
            %{
              "id" => cap.id,
              "meaning" => cap.meaning,
              "holder_principal_id" => cap.holder_principal_id || cap.holder
            }
        end,
      "bootstrap_holders" => state.bootstrap_holders,
      "capabilities" => Enum.map(state.capabilities, &cap_to_json/1),
      "cot" => state.cot
    }
  end

  defp cap_to_json(c) do
    %{
      "id" => c.id,
      "holder" => c.holder,
      "verb" => c.verb,
      "resource" => c.resource,
      "alpha" => c.alpha,
      "beta" => c.beta,
      "omega" => c.omega,
      "workspace_cid" => c.workspace_cid,
      "meaning" => c.meaning
    }
  end

  defp from_json(map) do
    holders = map["bootstrap_holders"] || []
    principals = Enum.map(map["principals"] || [], &principal_from_json/1)

    genesis =
      Map.get(map, "genesis_complete", holders != [] and principals != [])

    boot_cap =
      case map["bootstrap_capability"] do
        nil ->
          nil

        cap ->
          %{
            id: cap["id"],
            meaning: cap["meaning"],
            holder_principal_id: cap["holder_principal_id"],
            holder: cap["holder_principal_id"],
            verb: "bootstrap",
            resource: "*",
            alpha: 0,
            beta: 0,
            omega: 0,
            workspace_cid: nil
          }
      end

    %{
      node_id: map["node_id"] || "node-1",
      created_at: map["created_at"] || now(),
      principals: principals,
      bootstrap_capability: boot_cap,
      bootstrap_holders: holders,
      capabilities: Enum.map(map["capabilities"] || [], &cap_from_json/1),
      genesis_complete: genesis,
      cot: map["cot"] || %{}
    }
  end

  defp principal_from_json(p) do
    %{
      id: p["id"],
      display_name: p["display_name"],
      role: p["role"],
      public_key: p["public_key"] || p["id"],
      created_at: p["created_at"]
    }
  end

  defp cap_from_json(c) do
    %{
      id: c["id"],
      holder: c["holder"],
      verb: c["verb"],
      resource: c["resource"] || "*",
      alpha: c["alpha"] || 0,
      beta: c["beta"] || 0,
      omega: c["omega"] || 0,
      workspace_cid: c["workspace_cid"],
      meaning: c["meaning"] || c["verb"]
    }
  end

  defp short_id do
    :crypto.strong_rand_bytes(6) |> Base.url_encode64(padding: false)
  end

  defp now, do: DateTime.utc_now() |> DateTime.to_iso8601()
end
