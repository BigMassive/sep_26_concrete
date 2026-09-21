defmodule ConcreteRuntime.Lab do
  @moduledoc """
  Lab supervisor god-view: `powered`, `boot_stage`, `zeroised`, this node's EK.

  Labelled harness — never holds the bootstrap capability (ADR 0004 / 0005).
  Zeroise vs stale D2/G on chain is named, not fully specified: the flag is
  enough to re-enter King-making.

  Power / zeroise / genesis flags live in `:persistent_term` so `Bootstrap`
  and `Lab` never `GenServer.call` each other (deadlock ⇒ half-CoT).
  """
  use GenServer

  @flags_key {__MODULE__, :flags}

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def flags do
    :persistent_term.get(@flags_key, %{
      powered: false,
      zeroised: false,
      genesis_complete: false,
      boot_stage: "off"
    })
  end

  def flag(key) when is_atom(key) do
    Map.get(flags(), key)
  end

  def status do
    case Process.whereis(__MODULE__) do
      nil ->
        f = flags()

        %{
          harness_note: "lab supervisor god-view — not cap holder",
          powered: f.powered,
          boot_stage: f.boot_stage,
          zeroised: f.zeroised,
          genesis_complete: f.genesis_complete,
          node_id: "node-1",
          ek_public_key: nil
        }

      _ ->
        GenServer.call(__MODULE__, :status)
    end
  end

  def powered?, do: flag(:powered) == true
  def zeroised?, do: flag(:zeroised) == true
  def genesis_complete?, do: flag(:genesis_complete) == true

  def ek_public_key do
    case Process.whereis(__MODULE__) do
      nil -> {:error, :lab_not_started}
      _ -> GenServer.call(__MODULE__, :ek)
    end
  end

  def set_powered(on) when is_boolean(on) do
    GenServer.call(__MODULE__, {:set_powered, on})
  end

  def mark_zeroised do
    GenServer.call(__MODULE__, :mark_zeroised)
  end

  def note_genesis(complete) when is_boolean(complete) do
    f = flags()

    boot =
      cond do
        not f.powered -> "off"
        complete -> "ready"
        true -> "chooser"
      end

    put_flags(%{
      genesis_complete: complete,
      boot_stage: boot,
      zeroised: if(complete, do: false, else: f.zeroised)
    })

    case Process.whereis(__MODULE__) do
      nil -> :ok
      pid -> GenServer.cast(pid, {:note_genesis, complete})
    end

    :ok
  end

  @impl true
  def init(opts) do
    data_dir = Keyword.fetch!(opts, :data_dir)
    path = Path.join(data_dir, "lab.json")
    state = load(path)

    put_flags(%{
      powered: state.powered,
      zeroised: state.zeroised,
      genesis_complete: false,
      boot_stage: state.boot_stage
    })

    {:ok, %{path: path, state: state}}
  end

  @impl true
  def handle_call(:status, _from, s) do
    genesis = flag(:genesis_complete) == true

    boot =
      cond do
        not s.state.powered -> "off"
        genesis -> "ready"
        true -> "chooser"
      end

    {:reply,
     %{
       harness_note: "lab supervisor god-view — not cap holder",
       powered: s.state.powered,
       boot_stage: boot,
       zeroised: s.state.zeroised,
       genesis_complete: genesis,
       node_id: "node-1",
       ek_public_key: s.state.ek_public_key
     }, %{s | state: %{s.state | boot_stage: boot}}}
  end

  def handle_call(:ek, _from, s), do: {:reply, {:ok, s.state.ek_public_key}, s}

  def handle_call({:set_powered, on}, _from, s) do
    put_flags(%{powered: on})

    if on do
      ConcreteRuntime.NodeSupervisor.on_power_on()
    else
      ConcreteRuntime.NodeSupervisor.on_power_off()
    end

    boot = boot_stage_now(on)
    state = %{s.state | powered: on, boot_stage: boot}
    persist!(s.path, state)
    put_flags(%{powered: on, boot_stage: boot})
    {:reply, :ok, %{s | state: state}}
  end

  def handle_call(:mark_zeroised, _from, s) do
    ek = new_ek()
    state = %{s.state | zeroised: true, ek_public_key: ek, boot_stage: "chooser"}
    persist!(s.path, state)
    put_flags(%{zeroised: true, boot_stage: "chooser"})
    {:reply, :ok, %{s | state: state}}
  end

  @impl true
  def handle_cast({:note_genesis, complete}, s) do
    boot = boot_stage_now(s.state.powered)

    state = %{
      s.state
      | zeroised: if(complete, do: false, else: s.state.zeroised),
        boot_stage: boot
    }

    persist!(s.path, state)
    {:noreply, %{s | state: state}}
  end

  defp boot_stage_now(powered) do
    cond do
      not powered -> "off"
      flag(:genesis_complete) -> "ready"
      true -> "chooser"
    end
  end

  defp put_flags(map) when is_map(map) do
    :persistent_term.put(@flags_key, Map.merge(flags(), map))
  end

  defp load(path) do
    if File.exists?(path) do
      path
      |> File.read!()
      |> Jason.decode!()
      |> from_json()
    else
      state = %{
        powered: true,
        boot_stage: "chooser",
        zeroised: false,
        ek_public_key: new_ek()
      }

      persist!(path, state)
      state
    end
  end

  defp persist!(path, state) do
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, Jason.encode!(to_json(state), pretty: true))
  end

  defp to_json(state) do
    %{
      "powered" => state.powered,
      "boot_stage" => state.boot_stage,
      "zeroised" => state.zeroised,
      "ek_public_key" => state.ek_public_key
    }
  end

  defp from_json(map) do
    %{
      powered: Map.get(map, "powered", true),
      boot_stage: Map.get(map, "boot_stage", "chooser"),
      zeroised: Map.get(map, "zeroised", false),
      ek_public_key: map["ek_public_key"] || new_ek()
    }
  end

  defp new_ek do
    "ek:node-1:" <> Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)
  end
end
