defmodule ConcreteRuntime.InfoObjects do
  @moduledoc """
  Named info objects, gated by bootstrap capability.

  Stages A–D (ADR 0007): Identity configured ⇒ fail-closed mutate, GET from
  ContentHead, API `did` is `did:iota:…`, and OTP persists an index
  (iota DID, ControllerCap id, label) with no authoritative head.
  Without a package, keep the Phase 1 lab DID path (`did:concrete:lab:<id>`).
  Leftover lab-DID objects remain addressable.
  """
  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def list(actor_id) when is_binary(actor_id) do
    GenServer.call(__MODULE__, {:list, actor_id})
  end

  def get(actor_id, did) when is_binary(actor_id) and is_binary(did) do
    GenServer.call(__MODULE__, {:get, actor_id, did}, 30_000)
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

  def create(principal_id, content, opts \\ []) do
    GenServer.call(__MODULE__, {:create, principal_id, content, opts}, 60_000)
  end

  def advance(principal_id, did, content, opts \\ []) do
    GenServer.call(__MODULE__, {:advance, principal_id, did, content, opts}, 60_000)
  end

  def add_link(principal_id, did, to_did, to_cid \\ nil) do
    GenServer.call(__MODULE__, {:add_link, principal_id, did, to_did, to_cid}, 60_000)
  end

  def add_reader(principal_id, did, public_key) do
    GenServer.call(__MODULE__, {:add_reader, principal_id, did, public_key})
  end

  def index_get(did) when is_binary(did) do
    GenServer.call(__MODULE__, {:index_get, did})
  end

  def link_permitted?(obj, actor_id) when is_map(obj) and is_binary(actor_id) do
    require_link_write(obj, actor_id)
  end

  def reset do
    case Process.whereis(__MODULE__) do
      nil -> :ok
      _ -> GenServer.call(__MODULE__, :reset)
    end
  end

  @impl true
  def init(opts) do
    data_dir = Keyword.fetch!(opts, :data_dir)
    path = Path.join(data_dir, "info_objects.json")
    state = load(path)
    {:ok, %{path: path, objects: state}}
  end

  @impl true
  def handle_call({:list, actor_id}, _from, s) do
    objects =
      s.objects
      |> Enum.filter(&readable?(&1, actor_id))
      |> Enum.map(&public/1)

    {:reply, objects, s}
  end

  def handle_call({:get, actor_id, did}, _from, s) do
    case find_object(s.objects, did) do
      nil ->
        {:reply, {:error, :not_found}, s}

      obj ->
        if readable?(obj, actor_id) do
          case hydrate(obj) do
            {:ok, public} -> {:reply, {:ok, public}, s}
            err -> {:reply, err, s}
          end
        else
          {:reply, {:error, :not_found}, s}
        end
    end
  end

  def handle_call({:snapshot, did}, _from, s) do
    {:reply, find_object(s.objects, did), s}
  end

  def handle_call({:restore, record}, _from, s) do
    objects =
      case find_object(s.objects, record.did) do
        nil -> s.objects ++ [record]
        _ -> replace_obj(s.objects, record, record)
      end

    persist!(s.path, objects)
    {:reply, :ok, %{s | objects: objects}}
  end

  def handle_call({:drop, did}, _from, s) do
    objects = Enum.reject(s.objects, fn o -> o.did == did or Map.get(o, :iota_did) == did end)
    persist!(s.path, objects)
    {:reply, :ok, %{s | objects: objects}}
  end

  def handle_call({:index_get, did}, _from, s) do
    {:reply, find_object(s.objects, did), s}
  end

  def handle_call(:reset, _from, s) do
    persist!(s.path, [])
    {:reply, :ok, %{s | objects: []}}
  end

  def handle_call({:add_link, principal_id, did, to_did, to_cid}, _from, s) do
    with {:ok, _, _} <- ConcreteRuntime.Bootstrap.authorize(principal_id, "write-info"),
         obj when not is_nil(obj) <- find_object(s.objects, did),
         :ok <- require_link_write(obj, principal_id),
         :ok <- require_ipfs(),
         {:ok, updated} <-
           rewrite_content(obj, principal_id, fn o ->
             Map.put(o, :links, put_link(Map.get(o, :links, []), %{did: to_did, cid: to_cid}))
           end) do
      objects = replace_obj(s.objects, obj, updated)
      persist!(s.path, objects)
      {:reply, :ok, %{s | objects: objects}}
    else
      nil -> {:reply, {:error, :not_found}, s}
      {:error, _} = err -> {:reply, err, s}
    end
  end

  def handle_call({:add_reader, principal_id, did, public_key}, _from, s) do
    with {:ok, _, _} <- ConcreteRuntime.Bootstrap.authorize(principal_id, "write-info"),
         obj when not is_nil(obj) <- find_object(s.objects, did),
         :ok <- require_write(obj, principal_id),
         :ok <- require_ipfs(),
         {:ok, updated} <-
           rewrite_content(obj, principal_id, fn o ->
             Map.put(o, :read_list, Enum.uniq((Map.get(o, :read_list) || []) ++ [public_key]))
           end) do
      objects = replace_obj(s.objects, obj, updated)
      persist!(s.path, objects)
      {:reply, :ok, %{s | objects: objects}}
    else
      nil -> {:reply, {:error, :not_found}, s}
      {:error, _} = err -> {:reply, err, s}
    end
  end

  def handle_call({:create, principal_id, content, opts}, _from, s) do
    with {:ok, _, _} <- ConcreteRuntime.Bootstrap.authorize(principal_id, "write-info"),
         :ok <- ConcreteRuntime.Vault.require_usable(principal_id),
         :ok <- require_ipfs(),
         {:ok, checkpoint} <- optional_iota_checkpoint(),
         {:ok, obj} <- build_new(principal_id, content, opts, checkpoint),
         {:ok, obj} <- attach_iota_identity(obj) do
      obj = index_record(obj)
      objects = s.objects ++ [obj]
      persist!(s.path, objects)
      state = %{s | objects: objects}

      case hydrate(obj) do
        {:ok, public} -> {:reply, {:ok, public}, state}
        {:error, _} = err -> {:reply, err, state}
      end
    else
      {:error, :capability_denied} = err ->
        {:reply, err, s}

      {:error, _} = err ->
        {:reply, err, s}
    end
  end

  def handle_call({:advance, principal_id, did, content, opts}, _from, s) do
    with {:ok, _, _} <- ConcreteRuntime.Bootstrap.authorize(principal_id, "write-info"),
         :ok <- ConcreteRuntime.Vault.require_usable(principal_id),
         :ok <- require_ipfs(),
         obj when not is_nil(obj) <- find_object(s.objects, did),
         :ok <- require_write(obj, principal_id),
         {:ok, checkpoint} <- optional_iota_checkpoint(),
         {:ok, updated} <- build_advance(obj, principal_id, content, opts, checkpoint),
         {:ok, updated} <- sync_iota_head(updated) do
      updated = index_record(updated)
      objects = Enum.map(s.objects, fn o -> if o.did == obj.did, do: updated, else: o end)
      persist!(s.path, objects)
      state = %{s | objects: objects}

      case hydrate(updated) do
        {:ok, public} -> {:reply, {:ok, public}, state}
        {:error, _} = err -> {:reply, err, state}
      end
    else
      nil ->
        {:reply, {:error, :not_found}, s}

      {:error, :capability_denied} = err ->
        {:reply, err, s}

      {:error, _} = err ->
        {:reply, err, s}
    end
  end

  defp build_new(principal_id, content, opts, checkpoint) do
    label = Keyword.get(opts, :label) || "info"
    message = Keyword.get(opts, :message) || "initial commit"
    read_list = Keyword.get(opts, :read_list) || [principal_id]
    write_list = Keyword.get(opts, :write_list) || [principal_id]
    links = encode_links(Keyword.get(opts, :links, []))

    with {:ok, content_cid} <-
           ipfs().add_json(%{
             "type" => "ConcreteContentBlob",
             "text" => content,
             "read_list" => read_list,
             "write_list" => write_list,
             "links" => links_json(links)
           }),
         commit = %{
           "type" => "ConcreteCommit",
           "message" => message,
           "content_cid" => content_cid,
           "parent_cid" => nil,
           "author_principal_id" => principal_id
         },
         {:ok, head_cid} <- ipfs().add_json(commit) do
      if identity_mod().configured?() do
        {:ok,
         %{
           label: label,
           head_cid: head_cid,
           created_by: principal_id,
           read_list: read_list,
           write_list: write_list,
           links: links
         }}
      else
        did = "did:concrete:lab:#{short_id()}"

        with {:ok, did_doc_cid} <- put_lab_did_doc(did, principal_id, head_cid) do
          {:ok,
           %{
             did: did,
             label: label,
             did_doc_cid: did_doc_cid,
             head_cid: head_cid,
             content_cid: content_cid,
             created_by: principal_id,
             updated_by: principal_id,
             created_at: now(),
             updated_at: now(),
             iota_checkpoint: checkpoint,
             read_list: read_list,
             write_list: write_list,
             links: links
           }}
        end
      end
    end
  end

  defp build_advance(obj, principal_id, content, opts, checkpoint) do
    message = Keyword.get(opts, :message) || "advance"

    with {:ok, parent_cid, _} <- parent_head(obj),
         {:ok, content_cid} <-
           ipfs().add_json(%{
             "type" => "ConcreteContentBlob",
             "text" => content
           }),
         commit = %{
           "type" => "ConcreteCommit",
           "message" => message,
           "content_cid" => content_cid,
           "parent_cid" => parent_cid,
           "author_principal_id" => principal_id
         },
         {:ok, head_cid} <- ipfs().add_json(commit),
         {:ok, did_doc_cid} <- maybe_put_lab_did_doc(obj, head_cid) do
      {:ok,
       obj
       |> Map.put(:did_doc_cid, did_doc_cid)
       |> Map.put(:head_cid, head_cid)
       |> Map.put(:content_cid, content_cid)
       |> Map.put(:updated_by, principal_id)
       |> Map.put(:updated_at, now())
       |> Map.put(:iota_checkpoint, checkpoint)}
    end
  end

  defp rewrite_content(obj, actor_id, fun) when is_function(fun, 1) do
    with {:ok, head_cid, _} <- head_for_read(obj),
         {:ok, commit} <- ipfs().cat_json(head_cid),
         {:ok, blob} <- ipfs().cat_json(commit["content_cid"]) do
      next = fun.(obj)
      read_list = Map.get(next, :read_list) || blob["read_list"] || []
      write_list = Map.get(next, :write_list) || blob["write_list"] || []
      links = encode_links(Map.get(next, :links) || blob["links"] || [])

      with {:ok, content_cid} <-
             ipfs().add_json(%{
               "type" => "ConcreteContentBlob",
               "text" => blob["text"],
               "read_list" => read_list,
               "write_list" => write_list,
               "links" => links_json(links)
             }),
           {:ok, new_head} <-
             ipfs().add_json(%{
               "type" => "ConcreteCommit",
               "message" => "wendy-link / acl",
               "content_cid" => content_cid,
               "parent_cid" => head_cid,
               "author_principal_id" => actor_id
             }),
           {:ok, did_doc_cid} <- maybe_put_lab_did_doc(next, new_head) do
        updated =
          next
          |> Map.put(:head_cid, new_head)
          |> Map.put(:content_cid, content_cid)
          |> Map.put(:did_doc_cid, did_doc_cid)
          |> Map.put(:updated_by, actor_id)
          |> Map.put(:updated_at, now())
          |> Map.put(:read_list, read_list)
          |> Map.put(:write_list, write_list)
          |> Map.put(:links, links)

        case sync_iota_head(updated) do
          {:ok, synced} -> {:ok, index_record(synced)}
          {:error, _} = err -> err
        end
      end
    end
  end

  defp parent_head(obj) do
    case iota_name(obj) do
      did when is_binary(did) and did != "" ->
        head_for_read(obj)

      _ ->
        {:ok, obj.head_cid, "otp_registry"}
    end
  end

  defp maybe_put_lab_did_doc(obj, head_cid) do
    did = obj.did

    if is_binary(did) and String.starts_with?(did, "did:concrete:lab:") do
      put_lab_did_doc(did, Map.get(obj, :created_by), head_cid)
    else
      {:ok, Map.get(obj, :did_doc_cid)}
    end
  end

  defp put_lab_did_doc(did, controller, head_cid) do
    ipfs().add_json(%{
      "@context" => "https://www.w3.org/ns/did/v1",
      "id" => did,
      "controller" => controller,
      "service" => [
        %{
          "id" => "#{did}#head",
          "type" => "ContentHead",
          "serviceEndpoint" => "ipfs://#{head_cid}"
        }
      ]
    })
  end

  defp hydrate(obj) do
    with {:ok, head_cid, head_source} <- head_for_read(obj),
         {:ok, commit} <- ipfs().cat_json(head_cid),
         {:ok, blob} <- ipfs().cat_json(commit["content_cid"]) do
      {:ok,
       %{
         did: api_did(obj),
         label: obj.label,
         head_cid: head_cid,
         content_cid: commit["content_cid"],
         did_doc_cid: Map.get(obj, :did_doc_cid),
         content: blob["text"],
         commit_message: commit["message"],
         parent_cid: commit["parent_cid"],
         created_by: Map.get(obj, :created_by) || commit["author_principal_id"],
         updated_by: Map.get(obj, :updated_by) || commit["author_principal_id"],
         created_at: Map.get(obj, :created_at),
         updated_at: Map.get(obj, :updated_at),
         iota_checkpoint: Map.get(obj, :iota_checkpoint),
         iota_did: iota_name(obj),
         identity_object_id: Map.get(obj, :identity_object_id),
         controller_cap_id: Map.get(obj, :controller_cap_id),
         head_source: head_source,
         read_list: blob["read_list"] || Map.get(obj, :read_list) || [],
         write_list: blob["write_list"] || Map.get(obj, :write_list) || [],
         links: encode_links(blob["links"] || Map.get(obj, :links) || [])
       }}
    end
  end

  @doc false
  def head_for_read(obj) do
    case iota_name(obj) do
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
        {:ok, obj.head_cid, "otp_registry"}
    end
  end

  @doc false
  def find_object(objects, did) when is_list(objects) and is_binary(did) do
    Enum.find(objects, fn o ->
      o.did == did or Map.get(o, :iota_did) == did or api_did(o) == did
    end)
  end

  defp api_did(obj) do
    case iota_name(obj) do
      did when is_binary(did) and did != "" -> did
      _ -> obj.did
    end
  end

  defp iota_name(obj) do
    case Map.get(obj, :iota_did) do
      did when is_binary(did) and did != "" ->
        did

      _ ->
        case Map.get(obj, :did) do
          did when is_binary(did) ->
            if String.starts_with?(did, "did:iota:"), do: did, else: nil

          _ ->
            nil
        end
    end
  end

  defp public(obj) do
    if iota_name(obj) do
      %{
        did: api_did(obj),
        label: obj.label,
        iota_did: iota_name(obj),
        identity_object_id: Map.get(obj, :identity_object_id),
        controller_cap_id: Map.get(obj, :controller_cap_id)
      }
    else
      obj
      |> Map.take([
        :label,
        :head_cid,
        :content_cid,
        :did_doc_cid,
        :created_by,
        :updated_by,
        :created_at,
        :updated_at,
        :iota_checkpoint
      ])
      |> Map.put(:did, api_did(obj))
    end
  end

  @doc false
  def attach_iota_identity(obj) do
    mod = identity_mod()

    if mod.configured?() do
      case mod.create_and_publish(head_cid: obj.head_cid) do
        {:ok, created} ->
          iota_did = created.did
          oid = created.identity_object_id

          with :ok <- mod.require_on_chain_head(iota_did, obj.head_cid) do
            {:ok,
             Map.merge(obj, %{
               did: iota_did,
               iota_did: iota_did,
               identity_object_id: oid,
               controller_cap_id: Map.get(created, :controller_cap_id)
             })}
          end

        {:error, reason} ->
          {:error, {:iota_identity_create_failed, reason}}
      end
    else
      {:ok, obj}
    end
  end

  @doc false
  def sync_iota_head(obj) do
    mod = identity_mod()

    if mod.configured?() do
      case iota_name(obj) do
        did when is_binary(did) and did != "" ->
          case mod.update_head(did, obj.head_cid) do
            {:ok, resolved} ->
              with :ok <- ConcreteRuntime.IotaIdentity.match_on_chain_head(resolved, obj.head_cid) do
                {:ok, obj}
              end

            {:error, reason} ->
              {:error, {:iota_identity_update_failed, reason}}
          end

        _ ->
          {:error, :iota_did_missing}
      end
    else
      {:ok, obj}
    end
  end

  defp identity_mod do
    Application.get_env(:concrete_runtime, :iota_identity, ConcreteRuntime.IotaIdentity)
  end

  defp ipfs do
    Application.get_env(:concrete_runtime, :ipfs, ConcreteRuntime.IPFS)
  end

  defp require_ipfs do
    case ipfs().ping() do
      :ok -> :ok
      {:error, reason} -> {:error, {:ipfs_unavailable, reason}}
    end
  end

  defp optional_iota_checkpoint do
    case ConcreteRuntime.Iota.latest_checkpoint() do
      {:ok, cp} -> {:ok, cp}
      {:error, _} -> {:ok, nil}
    end
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

  defp persist!(path, objects) do
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, Jason.encode!(Enum.map(objects, &to_json/1), pretty: true))
  end

  @doc false
  def index_record(obj) do
    case iota_name(obj) do
      did when is_binary(did) and did != "" ->
        cap =
          Map.get(obj, :controller_cap_id) ||
            ConcreteRuntime.IotaIdentity.controller_cap_id(did)

        %{
          did: did,
          iota_did: did,
          identity_object_id: Map.get(obj, :identity_object_id),
          controller_cap_id: cap,
          label: obj.label,
          read_list: Map.get(obj, :read_list) || [],
          write_list: Map.get(obj, :write_list) || [],
          links: encode_links(Map.get(obj, :links, []))
        }

      _ ->
        obj
    end
  end

  defp to_json(o) do
    o = index_record(o)

    case iota_name(o) do
      did when is_binary(did) and did != "" ->
        %{
          "did" => did,
          "iota_did" => did,
          "identity_object_id" => Map.get(o, :identity_object_id),
          "controller_cap_id" => Map.get(o, :controller_cap_id),
          "label" => o.label,
          "read_list" => Map.get(o, :read_list) || [],
          "write_list" => Map.get(o, :write_list) || [],
          "links" => links_json(Map.get(o, :links, []))
        }

      _ ->
        %{
          "did" => o.did,
          "label" => o.label,
          "did_doc_cid" => Map.get(o, :did_doc_cid),
          "head_cid" => Map.get(o, :head_cid),
          "content_cid" => Map.get(o, :content_cid),
          "created_by" => Map.get(o, :created_by),
          "updated_by" => Map.get(o, :updated_by),
          "created_at" => Map.get(o, :created_at),
          "updated_at" => Map.get(o, :updated_at),
          "iota_checkpoint" => Map.get(o, :iota_checkpoint),
          "read_list" => Map.get(o, :read_list) || [],
          "write_list" => Map.get(o, :write_list) || [],
          "links" => links_json(Map.get(o, :links, []))
        }
    end
  end

  defp from_json(m) do
    iota =
      cond do
        is_binary(m["iota_did"]) and m["iota_did"] != "" -> m["iota_did"]
        is_binary(m["did"]) and String.starts_with?(m["did"], "did:iota:") -> m["did"]
        true -> nil
      end

    if iota do
      index_record(%{
        did: iota,
        iota_did: iota,
        identity_object_id: m["identity_object_id"],
        controller_cap_id: m["controller_cap_id"],
        label: m["label"],
        read_list: m["read_list"] || [],
        write_list: m["write_list"] || [],
        links: encode_links(m["links"] || [])
      })
    else
      %{
        did: m["did"],
        label: m["label"],
        did_doc_cid: m["did_doc_cid"],
        head_cid: m["head_cid"],
        content_cid: m["content_cid"],
        created_by: m["created_by"],
        updated_by: m["updated_by"],
        created_at: m["created_at"],
        updated_at: m["updated_at"],
        iota_checkpoint: m["iota_checkpoint"],
        read_list: m["read_list"] || [],
        write_list: m["write_list"] || [],
        links: encode_links(m["links"] || [])
      }
    end
  end

  defp readable?(obj, actor_id) do
    list = Map.get(obj, :read_list) || []

    match?({:ok, _, _}, ConcreteRuntime.Bootstrap.authorize(actor_id, "mutate")) or
      (is_list(list) and actor_id in list)
  end

  defp writable?(obj, actor_id) do
    list = Map.get(obj, :write_list) || []

    match?({:ok, _, _}, ConcreteRuntime.Bootstrap.authorize(actor_id, "mutate")) or
      (is_list(list) and actor_id in list)
  end

  defp require_write(obj, actor_id) do
    if writable?(obj, actor_id), do: :ok, else: {:error, :capability_denied}
  end

  # Wendy back-link: writer or a reader with write-info (Alice → G).
  defp require_link_write(obj, actor_id) do
    if writable?(obj, actor_id) or readable?(obj, actor_id) do
      :ok
    else
      {:error, :capability_denied}
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

  defp links_json(links) do
    Enum.map(encode_links(links), fn l -> %{"did" => l.did, "cid" => l.cid} end)
  end

  defp put_link(links, %{did: did} = link) do
    links = encode_links(links)

    case Enum.find(links, &(&1.did == did)) do
      nil -> links ++ [link]
      _ -> Enum.map(links, fn l -> if l.did == did, do: link, else: l end)
    end
  end

  defp replace_obj(objects, old, updated) do
    Enum.map(objects, fn o -> if o.did == old.did, do: updated, else: o end)
  end

  defp short_id do
    :crypto.strong_rand_bytes(8) |> Base.url_encode64(padding: false)
  end

  defp now, do: DateTime.utc_now() |> DateTime.to_iso8601()
end
