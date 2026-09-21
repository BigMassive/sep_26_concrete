defmodule ConcreteRuntime.Workspaces do
  @moduledoc """
  W0 / W1 / W2 orchestration. Workspaces are **data** (full GraphEdit layout)
  plus a **title** information object. Caps point at workspaces; GraphEdit
  cannot mint or widen authority. Locked graphs are denied server-side.
  """
  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def genesis(attrs) when is_map(attrs) do
    GenServer.call(__MODULE__, {:genesis, attrs}, 120_000)
  end

  def introduce_user(actor_id, attrs) when is_binary(actor_id) and is_map(attrs) do
    GenServer.call(__MODULE__, {:w1, actor_id, attrs}, 120_000)
  end

  def write_info(actor_id, attrs) when is_binary(actor_id) and is_map(attrs) do
    GenServer.call(__MODULE__, {:w2, actor_id, attrs}, 120_000)
  end

  def list(actor_id) when is_binary(actor_id) do
    GenServer.call(__MODULE__, {:list, actor_id})
  end

  def get(actor_id, workspace_id) when is_binary(actor_id) and is_binary(workspace_id) do
    GenServer.call(__MODULE__, {:get, actor_id, workspace_id})
  end

  def save_layout(actor_id, workspace_id, layout)
      when is_binary(actor_id) and is_binary(workspace_id) do
    GenServer.call(__MODULE__, {:save_layout, actor_id, workspace_id, layout}, 60_000)
  end

  def login(attrs) when is_map(attrs) do
    GenServer.call(__MODULE__, {:login, attrs}, 30_000)
  end

  def logout(actor_id) when is_binary(actor_id) do
    GenServer.call(__MODULE__, {:logout, actor_id})
  end

  def zeroise do
    GenServer.call(__MODULE__, :zeroise, 30_000)
  end

  def reset do
    GenServer.call(__MODULE__, :reset)
  end

  def w0_layout do
    %{
      "workspace_id" => "w0",
      "locked" => false,
      "system" => true,
      "nodes" => [
        %{"id" => "username", "title" => "Username", "x" => 40, "y" => 40, "type" => "text_in"},
        %{
          "id" => "public_key",
          "title" => "Public key",
          "x" => 40,
          "y" => 160,
          "type" => "text_in"
        },
        %{
          "id" => "private_key",
          "title" => "Private key (paper)",
          "x" => 40,
          "y" => 280,
          "type" => "text_in"
        },
        %{"id" => "pin", "title" => "PIN", "x" => 360, "y" => 40, "type" => "text_in"},
        %{"id" => "run", "title" => "Run genesis", "x" => 360, "y" => 200, "type" => "run"}
      ],
      "wires" => [
        ["username", "run"],
        ["public_key", "run"],
        ["private_key", "run"],
        ["pin", "run"]
      ]
    }
  end

  def w1_layout do
    %{
      "workspace_id" => "w1",
      "locked" => true,
      "nodes" => [
        %{"id" => "username", "title" => "Name", "x" => 40, "y" => 40, "type" => "text_in"},
        %{
          "id" => "public_key",
          "title" => "Public key",
          "x" => 40,
          "y" => 160,
          "type" => "text_in"
        },
        %{
          "id" => "pin",
          "title" => "PIN (show once)",
          "x" => 380,
          "y" => 40,
          "type" => "text_out"
        },
        %{"id" => "run", "title" => "Introduce user", "x" => 380, "y" => 200, "type" => "run"}
      ],
      "wires" => [["username", "run"], ["public_key", "run"], ["run", "pin"]]
    }
  end

  def w2_layout do
    %{
      "workspace_id" => "w2",
      "locked" => true,
      "nodes" => [
        %{"id" => "text", "title" => "Text", "x" => 40, "y" => 40, "type" => "text_in"},
        %{
          "id" => "readers",
          "title" => "Read (usernames)",
          "x" => 40,
          "y" => 160,
          "type" => "user_picker"
        },
        %{
          "id" => "writers",
          "title" => "Write (usernames)",
          "x" => 40,
          "y" => 300,
          "type" => "user_picker"
        },
        %{
          "id" => "link",
          "title" => "Wendy-link DID",
          "x" => 400,
          "y" => 40,
          "type" => "text_in"
        },
        %{"id" => "run", "title" => "Write information", "x" => 400, "y" => 200, "type" => "run"}
      ],
      "wires" => [["text", "run"], ["readers", "run"], ["writers", "run"], ["link", "run"]]
    }
  end

  @impl true
  def init(opts) do
    data_dir = Keyword.fetch!(opts, :data_dir)
    path = Path.join(data_dir, "workspaces.json")
    state = load(path)
    {:ok, %{path: path, workspaces: state}}
  end

  @impl true
  def handle_call({:genesis, attrs}, _from, s) do
    case run_genesis(attrs) do
      {:ok, result, workspaces} ->
        persist!(s.path, workspaces)
        {:reply, {:ok, result}, %{s | workspaces: workspaces}}

      {:error, reason} = err when reason in [:genesis_replay, :node_powered_off] ->
        {:reply, err, s}

      {:error, _} = err ->
        wipe_attempt()
        {:reply, err, %{s | workspaces: []}}
    end
  end

  def handle_call({:w1, actor_id, attrs}, _from, s) do
    {:reply, run_w1(actor_id, attrs, s.workspaces), s}
  end

  def handle_call({:w2, actor_id, attrs}, _from, s) do
    {:reply, run_w2(actor_id, attrs), s}
  end

  def handle_call({:list, actor_id}, _from, s) do
    runnable =
      Enum.filter(s.workspaces, fn w ->
        Map.get(w, :system) != true and can_run?(actor_id, w.id)
      end)

    {:reply, {:ok, Enum.map(runnable, &public_ws(&1, actor_id))}, s}
  end

  def handle_call({:get, actor_id, workspace_id}, _from, s) do
    cond do
      workspace_id == "w0" ->
        {:reply, {:ok, %{id: "w0", locked: false, system: true, layout: w0_layout()}}, s}

      true ->
        case Enum.find(s.workspaces, &(&1.id == workspace_id)) do
          nil ->
            {:reply, {:error, :not_found}, s}

          w ->
            if can_run?(actor_id, w.id) or bootstrap?(actor_id) do
              {:reply, {:ok, public_ws(w, actor_id)}, s}
            else
              {:reply, {:error, :capability_denied}, s}
            end
        end
    end
  end

  def handle_call({:save_layout, actor_id, workspace_id, _layout}, _from, s) do
    _ = actor_id

    reply =
      case Enum.find(s.workspaces, &(&1.id == workspace_id)) do
        nil when workspace_id == "w0" ->
          {:error, :graph_locked}

        nil ->
          {:error, :not_found}

        %{locked: true} ->
          {:error, :graph_locked}

        _ ->
          {:error, :graph_locked}
      end

    {:reply, reply, s}
  end

  def handle_call({:login, attrs}, _from, s) do
    {:reply, do_login(attrs), s}
  end

  def handle_call({:logout, actor_id}, _from, s) do
    cur = ConcreteRuntime.Session.current()

    reply =
      if cur.logged_in and (cur.principal_id == actor_id or bootstrap?(actor_id)) do
        ConcreteRuntime.Session.clear()
        :ok
      else
        {:error, :not_current_session}
      end

    {:reply, reply, s}
  end

  def handle_call(:zeroise, _from, s) do
    ConcreteRuntime.NodeSupervisor.terminate_all()
    ConcreteRuntime.Session.clear()
    ConcreteRuntime.Bootstrap.reset_empty()
    ConcreteRuntime.DataObjects.reset()
    ConcreteRuntime.InfoObjects.reset()
    ConcreteRuntime.UserDirectory.reset()
    persist!(s.path, [])
    ConcreteRuntime.Lab.mark_zeroised()
    {:reply, :ok, %{s | workspaces: []}}
  end

  def handle_call(:reset, _from, s) do
    persist!(s.path, [])
    {:reply, :ok, %{s | workspaces: []}}
  end

  defp run_genesis(attrs) do
    with :ok <- ConcreteRuntime.Bootstrap.ensure_can_genesis(),
         {:ok, helen} <- ConcreteRuntime.Bootstrap.begin_genesis(attrs),
         :ok <-
           ConcreteRuntime.Vault.ensure_import(
             helen.id,
             to_string(attrs[:private_key] || attrs["private_key"])
           ),
         {:ok, ek} <- ConcreteRuntime.Lab.ek_public_key(),
         pin <- to_string(attrs[:pin] || attrs["pin"]),
         {:ok, d1} <-
           ConcreteRuntime.DataObjects.create(helen.id, "d1", %{pubkeys: [helen.id]}, []),
         {:ok, d2} <-
           ConcreteRuntime.DataObjects.create(helen.id, "d2", %{eks: [ek]}, []),
         {:ok, d3} <-
           ConcreteRuntime.DataObjects.create(
             helen.id,
             "d3",
             %{pairs: [%{public_key: helen.id, username: helen.display_name}]},
             []
           ),
         {:ok, d4} <-
           ConcreteRuntime.DataObjects.create(
             helen.id,
             "d4",
             %{pairs: [%{public_key: helen.id, pin: pin}]},
             [],
             read_holders: :bootstrap
           ),
         {:ok, d5} <-
           ConcreteRuntime.DataObjects.create(
             helen.id,
             "d5",
             %{public_key: helen.id, username: helen.display_name},
             [],
             write_holders: [helen.id]
           ),
         ds <- [d1, d2, d3, d4, d5],
         {:ok, g} <-
           ConcreteRuntime.InfoObjects.create(helen.id, "Circle of Trust",
             label: "G",
             read_list: [helen.id],
             write_list: [helen.id],
             links: Enum.map(ds, &%{did: &1.did, cid: nil})
           ),
         :ok <- link_each(helen.id, ds, g.did),
         {:ok, w1} <- seed_workspace(helen, "w1", "Introduce user", w1_layout()),
         {:ok, w2} <- seed_workspace(helen, "w2", "Write information", w2_layout()),
         :ok <- grant_helen_caps(helen.id, w1, w2),
         {:ok, _} <- ConcreteRuntime.IdentityProcess.ensure_started(),
         {:ok, _} <-
           ConcreteRuntime.Session.put(helen, ConcreteRuntime.IdentityProcess.passing_abw()),
         cot <- %{
           "g_did" => g.did,
           "d1_did" => d1.did,
           "d2_did" => d2.did,
           "d3_did" => d3.did,
           "d4_did" => d4.did,
           "d5" => %{helen.id => d5.did}
         },
         :ok <- ConcreteRuntime.Bootstrap.finish_genesis(cot) do
      workspaces = [w1, w2]

      {:ok,
       %{
         principal: Map.take(helen, [:id, :display_name, :role, :public_key]),
         g_did: g.did,
         d1_did: d1.did,
         d2_did: d2.did,
         d3_did: d3.did,
         d4_did: d4.did,
         d5_did: d5.did,
         ek_public_key: ek,
         workspaces:
           Enum.map(workspaces, &Map.take(&1, [:id, :data_did, :data_cid, :title_did, :locked]))
       }, workspaces}
    end
  end

  defp run_w1(actor_id, attrs, workspaces) do
    cot = ConcreteRuntime.Bootstrap.cot_index()
    known_d5 = MapSet.new(Map.values(cot["d5"] || %{}))

    snaps = %{
      boot: ConcreteRuntime.Bootstrap.export_state(),
      d1: ConcreteRuntime.DataObjects.snapshot(cot["d1_did"]),
      d3: ConcreteRuntime.DataObjects.snapshot(cot["d3_did"]),
      d4: ConcreteRuntime.DataObjects.snapshot(cot["d4_did"]),
      g: ConcreteRuntime.InfoObjects.snapshot(cot["g_did"])
    }

    case w1_apply(actor_id, attrs, cot, workspaces) do
      {:ok, _} = ok ->
        ok

      {:error, _} = err ->
        restore_w1(snaps, known_d5)
        err
    end
  end

  defp w1_apply(actor_id, attrs, cot, workspaces) do
    with {:ok, _, _} <- ConcreteRuntime.Bootstrap.authorize(actor_id, "run-workspace", "w1"),
         {:ok, _, _} <- ConcreteRuntime.Bootstrap.authorize(actor_id, "introduce-user", "w1"),
         :ok <- ConcreteRuntime.Vault.require_usable(actor_id),
         username <- String.trim(to_string(attrs[:username] || attrs["username"] || "")),
         public_key <- String.trim(to_string(attrs[:public_key] || attrs["public_key"] || "")),
         true <- username != "" or {:error, :username_required},
         true <- String.starts_with?(public_key, "mldsa87:") or {:error, :public_key_required},
         {:ok, alice} <-
           ConcreteRuntime.Bootstrap.add_principal(actor_id, %{
             username: username,
             public_key: public_key
           }),
         pin <- five_digit_pin(),
         {:ok, _} <- append_d1(actor_id, cot["d1_did"], alice.id),
         {:ok, _} <- append_d3(actor_id, cot["d3_did"], alice.id, username),
         {:ok, _} <- append_d4(actor_id, cot["d4_did"], alice.id, pin),
         {:ok, d5} <-
           ConcreteRuntime.DataObjects.create(
             actor_id,
             "d5",
             %{public_key: alice.id, username: username},
             [%{did: cot["g_did"], cid: nil}],
             write_holders: [alice.id]
           ),
         :ok <-
           ConcreteRuntime.InfoObjects.add_link(actor_id, cot["g_did"], d5.did, nil),
         :ok <- add_reader_to_g(actor_id, cot["g_did"], alice.id),
         :ok <- ConcreteRuntime.Bootstrap.remember_d5(alice.id, d5.did),
         :ok <- grant_alice(actor_id, alice.id, workspaces) do
      {:ok,
       %{
         principal: Map.take(alice, [:id, :display_name, :role, :public_key]),
         pin: pin,
         d5_did: d5.did
       }}
    else
      false -> {:error, :invalid}
      {:error, _} = err -> err
      other -> {:error, other}
    end
  end

  defp restore_w1(snaps, known_d5) do
    ConcreteRuntime.Bootstrap.restore_state(snaps.boot)
    ConcreteRuntime.DataObjects.restore(snaps.d1)
    ConcreteRuntime.DataObjects.restore(snaps.d3)
    ConcreteRuntime.DataObjects.restore(snaps.d4)
    ConcreteRuntime.InfoObjects.restore(snaps.g)
    drop_unknown_d5(known_d5)
  end

  defp drop_unknown_d5(known) do
    Enum.each(ConcreteRuntime.DataObjects.dids_with_label("d5"), fn did ->
      if did not in known do
        ConcreteRuntime.DataObjects.drop(did)
      end
    end)
  end

  defp run_w2(actor_id, attrs) do
    text = to_string(attrs[:text] || attrs["text"] || attrs[:content] || attrs["content"] || "")
    link_did = attrs[:link_did] || attrs["link_did"]

    with {:ok, _, _} <- ConcreteRuntime.Bootstrap.authorize(actor_id, "run-workspace", "w2"),
         {:ok, _, _} <- ConcreteRuntime.Bootstrap.authorize(actor_id, "write-info"),
         :ok <- ConcreteRuntime.Vault.require_usable(actor_id),
         {:ok, readers} <- names_to_keys(attrs[:readers] || attrs["readers"] || []),
         {:ok, writers} <- names_to_keys(attrs[:writers] || attrs["writers"] || []),
         true <- String.trim(text) != "" or {:error, :content_required},
         cot <- ConcreteRuntime.Bootstrap.cot_index(),
         d5_did when is_binary(d5_did) <- d5_for(cot, actor_id),
         :ok <- prevalidate_link(actor_id, link_did) do
      readers = Enum.uniq(readers ++ [actor_id])
      writers = Enum.uniq(writers ++ [actor_id])
      d5_snap = ConcreteRuntime.DataObjects.snapshot(d5_did)
      target_snap = snapshot_link_target(link_did)

      case w2_commit(actor_id, text, readers, writers, link_did, d5_did) do
        {:ok, _} = ok ->
          ok

        {:error, created_did, reason} ->
          rollback_w2(created_did, d5_snap, target_snap, link_did)
          {:error, reason}

        {:error, _} = err ->
          err
      end
    else
      nil -> {:error, :no_d5}
      false -> {:error, :content_required}
      {:error, _} = err -> err
    end
  end

  defp w2_commit(actor_id, text, readers, writers, link_did, d5_did) do
    case ConcreteRuntime.InfoObjects.create(actor_id, text,
           label: "info",
           read_list: readers,
           write_list: writers,
           links: link_targets(link_did, d5_did)
         ) do
      {:error, _} = err ->
        err

      {:ok, obj} ->
        with :ok <- maybe_link_other(actor_id, obj.did, link_did),
             {:ok, _} <- ConcreteRuntime.DataObjects.add_link(actor_id, d5_did, obj.did, nil) do
          {:ok, obj}
        else
          {:error, reason} -> {:error, obj.did, reason}
        end
    end
  end

  defp rollback_w2(created_did, d5_snap, target_snap, link_did) do
    if is_binary(created_did), do: ConcreteRuntime.InfoObjects.drop(created_did)
    ConcreteRuntime.DataObjects.restore(d5_snap)
    restore_link_target(link_did, target_snap)
  end

  defp snapshot_link_target(link) when link in [nil, ""], do: nil

  defp snapshot_link_target(link_did) do
    case ConcreteRuntime.DataObjects.record(link_did) do
      rec when is_map(rec) -> {:data, rec}
      _ -> {:info, ConcreteRuntime.InfoObjects.snapshot(link_did)}
    end
  end

  defp restore_link_target(_link, nil), do: :ok
  defp restore_link_target(_link, {:data, rec}), do: ConcreteRuntime.DataObjects.restore(rec)
  defp restore_link_target(_link, {:info, rec}), do: ConcreteRuntime.InfoObjects.restore(rec)

  defp prevalidate_link(_actor_id, link) when link in [nil, ""], do: :ok

  defp prevalidate_link(actor_id, link_did) do
    cond do
      rec = ConcreteRuntime.DataObjects.record(link_did) ->
        if ConcreteRuntime.DataObjects.write_permitted?(actor_id, rec) do
          :ok
        else
          {:error, :capability_denied}
        end

      obj = ConcreteRuntime.InfoObjects.index_get(link_did) ->
        ConcreteRuntime.InfoObjects.link_permitted?(obj, actor_id)

      true ->
        {:error, :not_found}
    end
  end

  defp do_login(attrs) do
    username = String.trim(to_string(attrs[:username] || attrs["username"] || ""))
    pin = String.trim(to_string(attrs[:pin] || attrs["pin"] || ""))
    private_key = to_string(attrs[:private_key] || attrs["private_key"] || "")

    cur = ConcreteRuntime.Session.current()

    cond do
      not ConcreteRuntime.Lab.powered?() ->
        {:error, :node_powered_off}

      cur.logged_in and cur.username != username ->
        {:error, :session_occupied}

      String.trim(private_key) == "" ->
        {:error, :missing_private_key}

      true ->
        with {:ok, principal} <- ConcreteRuntime.IdentityProcess.verify(username, pin),
             true <-
               ConcreteRuntime.Bootstrap.has_cap?(principal.id, "use-vault", principal.id) or
                 {:error, :capability_denied},
             :ok <- ConcreteRuntime.Vault.ensure_import(principal.id, private_key),
             abw <- ConcreteRuntime.IdentityProcess.passing_abw(),
             {:ok, session} <- ConcreteRuntime.Session.put(principal, abw) do
          {:ok,
           %{
             session: session,
             principal: Map.take(principal, [:id, :display_name, :public_key]),
             vault: ConcreteRuntime.Vault.status(principal.id),
             note: "not signed HTTP — OTP trusts principal_id until ADR 0008-5"
           }}
        end
    end
  end

  defp seed_workspace(helen, id, title, layout) do
    with {:ok, title_obj} <-
           ConcreteRuntime.InfoObjects.create(helen.id, title,
             label: "workspace-title-#{id}",
             read_list: [helen.id],
             write_list: [helen.id]
           ),
         {:ok, data} <-
           ConcreteRuntime.DataObjects.create(
             helen.id,
             "workspace",
             %{workspace_id: id, locked: layout["locked"], layout: layout},
             [%{did: title_obj.did, cid: nil}]
           ),
         :ok <- ConcreteRuntime.InfoObjects.add_link(helen.id, title_obj.did, data.did, nil) do
      {:ok,
       %{
         id: id,
         data_did: data.did,
         data_cid: data.cid,
         title_did: title_obj.did,
         locked: layout["locked"] == true,
         system: false,
         layout: layout
       }}
    end
  end

  defp grant_helen_caps(helen_id, w1, w2) do
    Enum.each(
      [
        %{holder: helen_id, verb: "introduce-user", resource: "w1", workspace_cid: w1.data_cid},
        %{holder: helen_id, verb: "run-workspace", resource: "w1", workspace_cid: w1.data_cid},
        %{holder: helen_id, verb: "run-workspace", resource: "w2", workspace_cid: w2.data_cid},
        %{holder: helen_id, verb: "write-info", resource: "*"},
        %{holder: helen_id, verb: "discovery", resource: "*"},
        %{holder: helen_id, verb: "use-vault", resource: helen_id}
      ],
      fn cap -> ConcreteRuntime.Bootstrap.grant(helen_id, cap) end
    )

    :ok
  end

  defp grant_alice(actor_id, alice_id, workspaces) do
    w2 = Enum.find(workspaces, &(&1.id == "w2"))
    w2_cid = w2 && Map.get(w2, :data_cid)

    Enum.each(
      [
        %{holder: alice_id, verb: "home", resource: "*"},
        %{holder: alice_id, verb: "write-info", resource: "*"},
        %{holder: alice_id, verb: "discovery", resource: "*"},
        %{holder: alice_id, verb: "use-vault", resource: alice_id},
        %{holder: alice_id, verb: "run-workspace", resource: "w2", workspace_cid: w2_cid}
      ],
      fn cap -> ConcreteRuntime.Bootstrap.grant(actor_id, cap) end
    )

    :ok
  end

  defp link_each(actor_id, ds, g_did) do
    Enum.reduce_while(ds, :ok, fn d, :ok ->
      case ConcreteRuntime.DataObjects.add_link(actor_id, d.did, g_did, nil) do
        {:ok, _} -> {:cont, :ok}
        {:error, _} = err -> {:halt, err}
      end
    end)
  end

  defp append_d1(actor_id, did, pk) do
    rec = ConcreteRuntime.DataObjects.record(did)
    keys = rec.payload["pubkeys"] || []
    keys = Enum.uniq(keys ++ [pk])
    ConcreteRuntime.DataObjects.update(actor_id, did, %{pubkeys: keys}, rec.links)
  end

  defp append_d3(actor_id, did, pk, username) do
    rec = ConcreteRuntime.DataObjects.record(did)
    pairs = rec.payload["pairs"] || []
    pairs = pairs ++ [%{"public_key" => pk, "username" => username}]
    ConcreteRuntime.DataObjects.update(actor_id, did, %{pairs: pairs}, rec.links)
  end

  defp append_d4(actor_id, did, pk, pin) do
    rec = ConcreteRuntime.DataObjects.record(did)
    pairs = rec.payload["pairs"] || []
    pairs = pairs ++ [%{"public_key" => pk, "pin" => pin}]
    ConcreteRuntime.DataObjects.update(actor_id, did, %{pairs: pairs}, rec.links)
  end

  defp add_reader_to_g(actor_id, g_did, pk) do
    ConcreteRuntime.InfoObjects.add_reader(actor_id, g_did, pk)
  end

  defp names_to_keys(list) when is_list(list) do
    Enum.reduce_while(list, {:ok, []}, fn entry, {:ok, acc} ->
      name = to_string(entry) |> String.trim()

      cond do
        name == "" ->
          {:cont, {:ok, acc}}

        true ->
          case ConcreteRuntime.DataObjects.lookup_username(name) do
            {:ok, pair} -> {:cont, {:ok, acc ++ [pair.public_key]}}
            _ -> {:halt, {:error, :unknown_username}}
          end
      end
    end)
  end

  defp names_to_keys(_), do: {:error, :unknown_username}

  defp link_targets(nil, d5_did), do: [%{did: d5_did, cid: nil}]
  defp link_targets("", d5_did), do: [%{did: d5_did, cid: nil}]

  defp link_targets(link_did, d5_did) do
    [%{did: d5_did, cid: nil}, %{did: link_did, cid: nil}]
  end

  defp maybe_link_other(_actor, _new_did, link) when link in [nil, ""], do: :ok

  defp maybe_link_other(actor_id, new_did, link_did) do
    case ConcreteRuntime.DataObjects.record(link_did) do
      rec when is_map(rec) ->
        case ConcreteRuntime.DataObjects.add_link(actor_id, link_did, new_did, nil) do
          {:ok, _} -> :ok
          {:error, _} = err -> err
        end

      _ ->
        ConcreteRuntime.InfoObjects.add_link(actor_id, link_did, new_did, nil)
    end
  end

  defp d5_for(cot, actor_id) do
    d5 = cot["d5"] || %{}
    d5[actor_id]
  end

  defp can_run?(actor_id, workspace_id) do
    match?(
      {:ok, _, _},
      ConcreteRuntime.Bootstrap.authorize(actor_id, "run-workspace", workspace_id)
    )
  end

  defp bootstrap?(actor_id) do
    match?({:ok, _, _}, ConcreteRuntime.Bootstrap.authorize(actor_id, "mutate"))
  end

  defp public_ws(w, actor_id) do
    cot = ConcreteRuntime.Bootstrap.cot_index()

    %{
      id: w.id,
      data_did: w.data_did,
      data_cid: workspace_cid(w),
      title_did: w.title_did,
      locked: w.locked,
      layout: workspace_layout(w),
      usernames: if(w.id == "w2", do: ConcreteRuntime.DataObjects.usernames(), else: []),
      g_did: cot["g_did"],
      runnable: can_run?(actor_id, w.id)
    }
  end

  defp workspace_cid(w) do
    case ConcreteRuntime.DataObjects.record(w.data_did) do
      %{cid: cid} when is_binary(cid) -> cid
      _ -> Map.get(w, :data_cid)
    end
  end

  defp workspace_layout(w) do
    case ConcreteRuntime.DataObjects.record(w.data_did) do
      %{payload: payload} ->
        payload["layout"] || payload[:layout] || w.layout || layout_for(w.id)

      _ ->
        w.layout || layout_for(w.id)
    end
  end

  defp layout_for("w1"), do: w1_layout()
  defp layout_for("w2"), do: w2_layout()
  defp layout_for(_), do: %{}

  defp wipe_attempt do
    ConcreteRuntime.NodeSupervisor.terminate_all()
    ConcreteRuntime.Bootstrap.abort_genesis()
    ConcreteRuntime.DataObjects.reset()
    ConcreteRuntime.InfoObjects.reset()
    ConcreteRuntime.UserDirectory.reset()
    ConcreteRuntime.Session.clear()
  end

  defp five_digit_pin do
    n = rem(:binary.decode_unsigned(:crypto.strong_rand_bytes(4)), 90_000) + 10_000
    Integer.to_string(n)
  end

  defp load(path) do
    if File.exists?(path) do
      path
      |> File.read!()
      |> Jason.decode!()
      |> Enum.map(&ws_from_json/1)
    else
      []
    end
  end

  defp persist!(path, workspaces) do
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, Jason.encode!(Enum.map(workspaces, &ws_to_json/1), pretty: true))
  end

  defp ws_to_json(w) do
    %{
      "id" => w.id,
      "data_did" => w.data_did,
      "data_cid" => Map.get(w, :data_cid),
      "title_did" => w.title_did,
      "locked" => w.locked,
      "system" => Map.get(w, :system, false),
      "layout" => w.layout
    }
  end

  defp ws_from_json(m) do
    %{
      id: m["id"],
      data_did: m["data_did"],
      data_cid: m["data_cid"],
      title_did: m["title_did"],
      locked: m["locked"],
      system: m["system"] == true,
      layout: m["layout"]
    }
  end
end
