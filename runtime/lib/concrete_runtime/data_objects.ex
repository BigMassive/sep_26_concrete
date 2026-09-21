defmodule ConcreteRuntime.DataObjects do
  @moduledoc """
  Named **data** (stable DID, updatable CID, Wendy-link set). Not plaques:
  no commit graph / content-read-write information facets.

  Updating data = new IPFS bytes + same DID. D4 payload has a tight read cap
  (Helen/bootstrap + identity process). Discovery sees markers only.
  """
  use GenServer

  @blob_type "ConcreteDataObject"

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def list_markers(actor_id) when is_binary(actor_id) do
    GenServer.call(__MODULE__, {:list_markers, actor_id})
  end

  def get(actor_id, did) when is_binary(actor_id) and is_binary(did) do
    GenServer.call(__MODULE__, {:get, actor_id, did}, 30_000)
  end

  def create(actor_id, label, payload, links \\ [], opts \\ []) do
    GenServer.call(__MODULE__, {:create, actor_id, label, payload, links, opts}, 60_000)
  end

  def update(actor_id, did, payload, links) do
    GenServer.call(__MODULE__, {:update, actor_id, did, payload, links}, 60_000)
  end

  def add_link(actor_id, from_did, to_did, to_cid \\ nil) do
    GenServer.call(__MODULE__, {:add_link, actor_id, from_did, to_did, to_cid}, 60_000)
  end

  def snapshot(did) when is_binary(did) do
    GenServer.call(__MODULE__, {:snapshot, did})
  end

  def restore(nil), do: :ok

  def restore(record) when is_map(record) do
    GenServer.call(__MODULE__, {:restore, record})
  end

  def drop(did) when is_binary(did) do
    case Process.whereis(__MODULE__) do
      nil -> :ok
      _ -> GenServer.call(__MODULE__, {:drop, did})
    end
  end

  def reset do
    case Process.whereis(__MODULE__) do
      nil -> :ok
      _ -> GenServer.call(__MODULE__, :reset)
    end
  end

  def find_by_label(label) when is_binary(label) do
    GenServer.call(__MODULE__, {:find_by_label, label})
  end

  def dids_with_label(label) when is_binary(label) do
    GenServer.call(__MODULE__, {:dids_with_label, label})
  end

  def lookup_username(username) when is_binary(username) do
    GenServer.call(__MODULE__, {:lookup_username, username})
  end

  def member_d1(public_key) when is_binary(public_key) do
    GenServer.call(__MODULE__, {:member_d1, public_key})
  end

  def check_pin(public_key, pin) when is_binary(public_key) and is_binary(pin) do
    GenServer.call(__MODULE__, {:check_pin, public_key, pin})
  end

  def usernames do
    GenServer.call(__MODULE__, :usernames)
  end

  def record(did) when is_binary(did) do
    GenServer.call(__MODULE__, {:record, did})
  end

  @impl true
  def init(opts) do
    data_dir = Keyword.fetch!(opts, :data_dir)
    path = Path.join(data_dir, "data_objects.json")
    {:ok, %{path: path, records: load(path)}}
  end

  @impl true
  def handle_call({:list_markers, actor_id}, _from, s) do
    case ConcreteRuntime.Bootstrap.authorize(actor_id, "discovery") do
      {:ok, _, _} ->
        {:reply, {:ok, Enum.map(s.records, &marker/1)}, s}

      {:error, _} = err ->
        {:reply, err, s}
    end
  end

  def handle_call({:get, actor_id, did}, _from, s) do
    case find_record(s.records, did) do
      nil ->
        {:reply, {:error, :not_found}, s}

      rec ->
        if payload_readable?(rec, actor_id, s.records) do
          {:reply, hydrate(rec), s}
        else
          {:reply, {:ok, marker(rec)}, s}
        end
    end
  end

  def handle_call({:create, actor_id, label, payload, links, opts}, _from, s) do
    with {:ok, _, _} <- ConcreteRuntime.Bootstrap.authorize(actor_id, "mutate"),
         :ok <- require_ipfs() do
      read_holders = Keyword.get(opts, :read_holders, :members)
      write_holders = Keyword.get(opts, :write_holders, :bootstrap)

      case write_new(actor_id, label, payload, links, read_holders, write_holders) do
        {:ok, rec} ->
          records = s.records ++ [rec]
          persist!(s.path, records)
          {:reply, {:ok, public(rec)}, %{s | records: records}}

        {:error, _} = err ->
          {:reply, err, s}
      end
    else
      {:error, _} = err -> {:reply, err, s}
    end
  end

  def handle_call({:update, actor_id, did, payload, links}, _from, s) do
    with {:ok, _, _} <- ConcreteRuntime.Bootstrap.authorize(actor_id, "mutate"),
         rec when not is_nil(rec) <- find_record(s.records, did),
         :ok <- require_ipfs() do
      case rewrite(rec, payload, links) do
        {:ok, updated} ->
          records = replace(s.records, rec.did, updated)
          persist!(s.path, records)
          {:reply, {:ok, public(updated)}, %{s | records: records}}

        {:error, _} = err ->
          {:reply, err, s}
      end
    else
      nil -> {:reply, {:error, :not_found}, s}
      {:error, _} = err -> {:reply, err, s}
    end
  end

  def handle_call({:add_link, actor_id, from_did, to_did, to_cid}, _from, s) do
    with {:ok, _, _} <- ConcreteRuntime.Bootstrap.authorize(actor_id, "write-info"),
         rec when not is_nil(rec) <- find_record(s.records, from_did),
         :ok <- require_write(rec, actor_id),
         :ok <- require_ipfs() do
      link = %{did: to_did, cid: to_cid}
      links = put_link(rec.links, link)

      case rewrite(rec, rec.payload, links) do
        {:ok, updated} ->
          records = replace(s.records, rec.did, updated)
          persist!(s.path, records)
          {:reply, {:ok, public(updated)}, %{s | records: records}}

        {:error, _} = err ->
          {:reply, err, s}
      end
    else
      nil -> {:reply, {:error, :not_found}, s}
      {:error, _} = err -> {:reply, err, s}
    end
  end

  def handle_call({:snapshot, did}, _from, s) do
    {:reply, find_record(s.records, did), s}
  end

  def handle_call({:restore, record}, _from, s) do
    records =
      case find_record(s.records, record.did) do
        nil -> s.records ++ [record]
        _ -> replace(s.records, record.did, record)
      end

    persist!(s.path, records)
    {:reply, :ok, %{s | records: records}}
  end

  def handle_call({:drop, did}, _from, s) do
    records = Enum.reject(s.records, fn r -> r.did == did or iota_name(r) == did end)
    persist!(s.path, records)
    {:reply, :ok, %{s | records: records}}
  end

  def handle_call(:reset, _from, s) do
    persist!(s.path, [])
    {:reply, :ok, %{s | records: []}}
  end

  def handle_call({:find_by_label, label}, _from, s) do
    {:reply, Enum.find(s.records, &(&1.label == label)), s}
  end

  def handle_call({:dids_with_label, label}, _from, s) do
    {:reply, for(r <- s.records, r.label == label, do: r.did), s}
  end

  def handle_call({:lookup_username, username}, _from, s) do
    d3 = Enum.find(s.records, &(&1.label == "d3"))

    reply =
      case d3 &&
             Enum.find(pairs(d3), fn p ->
               p["username"] == username or p[:username] == username
             end) do
        nil ->
          {:error, :unknown_username}

        pair ->
          {:ok,
           %{
             public_key: pair["public_key"] || pair[:public_key],
             username: pair["username"] || pair[:username]
           }}
      end

    {:reply, reply, s}
  end

  def handle_call({:member_d1, public_key}, _from, s) do
    d1 = Enum.find(s.records, &(&1.label == "d1"))
    keys = (d1 && d1.payload["pubkeys"]) || (d1 && d1.payload[:pubkeys]) || []

    reply = if public_key in keys, do: :ok, else: {:error, :not_on_d1}
    {:reply, reply, s}
  end

  def handle_call({:check_pin, public_key, pin}, _from, s) do
    d4 = Enum.find(s.records, &(&1.label == "d4"))

    reply =
      case d4 &&
             Enum.find(pairs(d4), fn p -> (p["public_key"] || p[:public_key]) == public_key end) do
        nil ->
          {:error, :pin_mismatch}

        pair ->
          stored = to_string(pair["pin"] || pair[:pin] || "")
          if stored == pin, do: :ok, else: {:error, :pin_mismatch}
      end

    {:reply, reply, s}
  end

  def handle_call(:usernames, _from, s) do
    d3 = Enum.find(s.records, &(&1.label == "d3"))

    names =
      (d3 &&
         Enum.map(pairs(d3), fn p ->
           %{
             username: p["username"] || p[:username],
             public_key: p["public_key"] || p[:public_key]
           }
         end)) || []

    {:reply, names, s}
  end

  def handle_call({:record, did}, _from, s) do
    {:reply, find_record(s.records, did), s}
  end

  defp write_new(actor_id, label, payload, links, read_holders, write_holders) do
    rec0 = %{
      label: label,
      kind: "data",
      payload: stringify_keys(payload),
      links: encode_links(links),
      read_holders: read_holders,
      write_holders: write_holders,
      created_by: actor_id
    }

    blob = blob_map(rec0)

    with {:ok, cid} <- ipfs().add_json(blob),
         {:ok, rec} <- attach_name(Map.put(rec0, :cid, cid)) do
      {:ok, rec}
    end
  end

  defp rewrite(rec, payload, links) do
    updated = %{
      rec
      | payload: stringify_keys(payload),
        links: encode_links(links)
    }

    blob = blob_map(updated)

    with {:ok, cid} <- ipfs().add_json(blob),
         {:ok, named} <- sync_head(%{updated | cid: cid}) do
      {:ok, named}
    end
  end

  defp blob_map(rec) do
    %{
      "type" => @blob_type,
      "kind" => "data",
      "label" => rec.label,
      "payload" => stringify_keys(rec.payload),
      "links" => encode_links(rec.links)
    }
  end

  defp attach_name(rec) do
    mod = identity_mod()

    if mod.configured?() do
      case mod.create_and_publish(head_cid: rec.cid) do
        {:ok, created} ->
          did = created.did

          with :ok <- mod.require_on_chain_head(did, rec.cid) do
            {:ok,
             Map.merge(rec, %{
               did: did,
               iota_did: did,
               identity_object_id: created.identity_object_id,
               controller_cap_id: Map.get(created, :controller_cap_id)
             })}
          end

        {:error, reason} ->
          {:error, {:iota_identity_create_failed, reason}}
      end
    else
      {:ok,
       Map.merge(rec, %{
         did: "did:concrete:lab:data:#{short_id()}",
         iota_did: nil
       })}
    end
  end

  defp sync_head(rec) do
    mod = identity_mod()

    case iota_name(rec) do
      did when is_binary(did) and did != "" ->
        if mod.configured?() do
          case mod.update_head(did, rec.cid) do
            {:ok, resolved} ->
              with :ok <- ConcreteRuntime.IotaIdentity.match_on_chain_head(resolved, rec.cid) do
                {:ok, rec}
              end

            {:error, reason} ->
              {:error, {:iota_identity_update_failed, reason}}
          end
        else
          {:ok, rec}
        end

      _ ->
        {:ok, rec}
    end
  end

  defp hydrate(rec) do
    with {:ok, cid, source} <- cid_for_read(rec),
         {:ok, blob} <- ipfs().cat_json(cid) do
      {:ok,
       public(rec)
       |> Map.put(:cid, cid)
       |> Map.put(:cid_source, source)
       |> Map.put(:payload, blob["payload"] || rec.payload)
       |> Map.put(:links, encode_links(blob["links"] || rec.links))}
    end
  end

  defp cid_for_read(rec) do
    case iota_name(rec) do
      did when is_binary(did) and did != "" ->
        case identity_mod().resolve(did) do
          {:ok, resolved} ->
            case ConcreteRuntime.IotaIdentity.on_chain_head_cid(resolved) do
              {:ok, cid} -> {:ok, cid, "on_chain"}
              {:error, _} = err -> err
            end

          {:error, reason} ->
            {:error, {:iota_resolve_failed, reason}}
        end

      _ ->
        {:ok, rec.cid, "otp_index"}
    end
  end

  defp payload_readable?(rec, actor_id, records) do
    case rec.read_holders do
      :bootstrap ->
        bootstrap?(actor_id)

      :members ->
        bootstrap?(actor_id) or d1_member?(records, actor_id)

      list when is_list(list) ->
        actor_id in list

      _ ->
        false
    end
  end

  def write_permitted?(actor_id, rec) when is_binary(actor_id) and is_map(rec) do
    require_write(rec, actor_id) == :ok
  end

  defp require_write(rec, actor_id) do
    cond do
      bootstrap?(actor_id) ->
        :ok

      rec.write_holders == :bootstrap ->
        {:error, :capability_denied}

      is_list(rec.write_holders) and actor_id in rec.write_holders ->
        :ok

      rec.label == "d5" and (rec.payload["public_key"] || rec.payload[:public_key]) == actor_id ->
        :ok

      true ->
        {:error, :capability_denied}
    end
  end

  defp bootstrap?(actor_id) do
    match?({:ok, _, _}, ConcreteRuntime.Bootstrap.authorize(actor_id, "mutate"))
  end

  defp d1_member?(records, actor_id) do
    d1 = Enum.find(records, &(&1.label == "d1"))
    keys = (d1 && (d1.payload["pubkeys"] || d1.payload[:pubkeys] || [])) || []
    actor_id in keys
  end

  defp marker(rec) do
    %{
      did: rec.did,
      label: rec.label,
      kind: "data",
      marker: true,
      links: encode_links(rec.links)
    }
  end

  defp public(rec) do
    %{
      did: rec.did,
      iota_did: iota_name(rec),
      cid: rec.cid,
      label: rec.label,
      kind: "data",
      payload: rec.payload,
      links: encode_links(rec.links),
      read_holders: rec.read_holders,
      write_holders: Map.get(rec, :write_holders, :bootstrap),
      identity_object_id: Map.get(rec, :identity_object_id),
      controller_cap_id: Map.get(rec, :controller_cap_id)
    }
  end

  defp pairs(rec) do
    p = rec.payload["pairs"] || rec.payload[:pairs] || []
    p
  end

  defp put_link(links, %{did: did} = link) do
    links = encode_links(links)

    case Enum.find(links, &(&1.did == did)) do
      nil -> links ++ [link]
      _ -> Enum.map(links, fn l -> if l.did == did, do: link, else: l end)
    end
  end

  defp encode_links(nil), do: []

  defp encode_links(list) when is_list(list) do
    Enum.map(list, fn
      %{did: did} = l -> %{did: did, cid: Map.get(l, :cid)}
      %{"did" => did} = l -> %{did: did, cid: l["cid"]}
      did when is_binary(did) -> %{did: did, cid: nil}
    end)
  end

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), stringify_val(v)}
      {k, v} -> {k, stringify_val(v)}
    end)
  end

  defp stringify_keys(other), do: other

  defp stringify_val(list) when is_list(list), do: Enum.map(list, &stringify_val/1)
  defp stringify_val(map) when is_map(map), do: stringify_keys(map)
  defp stringify_val(other), do: other

  defp find_record(records, did) do
    Enum.find(records, fn r -> r.did == did or iota_name(r) == did end)
  end

  defp replace(records, did, updated) do
    Enum.map(records, fn r -> if r.did == did or iota_name(r) == did, do: updated, else: r end)
  end

  defp iota_name(rec) do
    case Map.get(rec, :iota_did) do
      did when is_binary(did) and did != "" ->
        did

      _ ->
        did = Map.get(rec, :did)
        if is_binary(did) and String.starts_with?(did, "did:iota:"), do: did, else: nil
    end
  end

  defp require_ipfs do
    case ipfs().ping() do
      :ok -> :ok
      {:error, reason} -> {:error, {:ipfs_unavailable, reason}}
    end
  end

  defp identity_mod do
    Application.get_env(:concrete_runtime, :iota_identity, ConcreteRuntime.IotaIdentity)
  end

  defp ipfs do
    Application.get_env(:concrete_runtime, :ipfs, ConcreteRuntime.IPFS)
  end

  defp load(path) do
    if File.exists?(path) do
      path
      |> File.read!()
      |> Jason.decode!()
      |> Enum.map(&from_json/1)
    else
      []
    end
  end

  defp persist!(path, records) do
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, Jason.encode!(Enum.map(records, &to_json/1), pretty: true))
  end

  defp to_json(r) do
    %{
      "did" => r.did,
      "iota_did" => iota_name(r),
      "cid" => r.cid,
      "label" => r.label,
      "kind" => "data",
      "payload" => stringify_keys(r.payload),
      "links" => Enum.map(encode_links(r.links), fn l -> %{"did" => l.did, "cid" => l.cid} end),
      "read_holders" => encode_holders(r.read_holders),
      "write_holders" => encode_holders(Map.get(r, :write_holders, :bootstrap)),
      "created_by" => Map.get(r, :created_by),
      "identity_object_id" => Map.get(r, :identity_object_id),
      "controller_cap_id" => Map.get(r, :controller_cap_id)
    }
  end

  defp from_json(m) do
    %{
      did: m["did"],
      iota_did: m["iota_did"],
      cid: m["cid"],
      label: m["label"],
      kind: "data",
      payload: m["payload"] || %{},
      links: encode_links(m["links"] || []),
      read_holders: decode_holders(m["read_holders"]),
      write_holders: decode_holders(m["write_holders"] || "bootstrap"),
      created_by: m["created_by"],
      identity_object_id: m["identity_object_id"],
      controller_cap_id: m["controller_cap_id"]
    }
  end

  defp encode_holders(:bootstrap), do: "bootstrap"
  defp encode_holders(:members), do: "members"
  defp encode_holders(list) when is_list(list), do: list
  defp encode_holders(_), do: "members"

  defp decode_holders("bootstrap"), do: :bootstrap
  defp decode_holders("members"), do: :members
  defp decode_holders(list) when is_list(list), do: list
  defp decode_holders(_), do: :members

  defp short_id do
    :crypto.strong_rand_bytes(8) |> Base.url_encode64(padding: false)
  end
end
