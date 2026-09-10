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

  def list, do: GenServer.call(__MODULE__, :list)
  def get(did), do: GenServer.call(__MODULE__, {:get, did}, 30_000)

  def create(principal_id, content, opts \\ []) do
    GenServer.call(__MODULE__, {:create, principal_id, content, opts}, 60_000)
  end

  def advance(principal_id, did, content, opts \\ []) do
    GenServer.call(__MODULE__, {:advance, principal_id, did, content, opts}, 60_000)
  end

  @impl true
  def init(opts) do
    data_dir = Keyword.fetch!(opts, :data_dir)
    path = Path.join(data_dir, "info_objects.json")
    state = load(path)
    {:ok, %{path: path, objects: state}}
  end

  @impl true
  def handle_call(:list, _from, s) do
    {:reply, Enum.map(s.objects, &public/1), s}
  end

  def handle_call({:get, did}, _from, s) do
    case find_object(s.objects, did) do
      nil ->
        {:reply, {:error, :not_found}, s}

      obj ->
        case hydrate(obj) do
          {:ok, public} -> {:reply, {:ok, public}, s}
          err -> {:reply, err, s}
        end
    end
  end

  def handle_call({:create, principal_id, content, opts}, _from, s) do
    with {:ok, _, _} <- ConcreteRuntime.Bootstrap.authorize(principal_id, "mutate"),
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
    with {:ok, _, _} <- ConcreteRuntime.Bootstrap.authorize(principal_id, "mutate"),
         :ok <- require_ipfs(),
         obj when not is_nil(obj) <- find_object(s.objects, did),
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

    with {:ok, content_cid} <-
           ConcreteRuntime.IPFS.add_json(%{
             "type" => "ConcreteContentBlob",
             "text" => content
           }),
         commit = %{
           "type" => "ConcreteCommit",
           "message" => message,
           "content_cid" => content_cid,
           "parent_cid" => nil,
           "author_principal_id" => principal_id
         },
         {:ok, head_cid} <- ConcreteRuntime.IPFS.add_json(commit) do
      if identity_mod().configured?() do
        {:ok,
         %{
           label: label,
           head_cid: head_cid,
           created_by: principal_id
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
             iota_checkpoint: checkpoint
           }}
        end
      end
    end
  end

  defp build_advance(obj, principal_id, content, opts, checkpoint) do
    message = Keyword.get(opts, :message) || "advance"

    with {:ok, parent_cid, _} <- parent_head(obj),
         {:ok, content_cid} <-
           ConcreteRuntime.IPFS.add_json(%{
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
         {:ok, head_cid} <- ConcreteRuntime.IPFS.add_json(commit),
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
    ConcreteRuntime.IPFS.add_json(%{
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
         {:ok, commit} <- ConcreteRuntime.IPFS.cat_json(head_cid),
         {:ok, blob} <- ConcreteRuntime.IPFS.cat_json(commit["content_cid"]) do
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
         head_source: head_source
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

  defp require_ipfs do
    case ConcreteRuntime.IPFS.ping() do
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
          label: obj.label
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
          "label" => o.label
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
          "iota_checkpoint" => Map.get(o, :iota_checkpoint)
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
        label: m["label"]
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
        iota_checkpoint: m["iota_checkpoint"]
      }
    end
  end

  defp short_id do
    :crypto.strong_rand_bytes(8) |> Base.url_encode64(padding: false)
  end

  defp now, do: DateTime.utc_now() |> DateTime.to_iso8601()
end
