defmodule ConcreteRuntime.TestKit do
  @moduledoc false

  defmodule Store do
    use Agent

    def start_link(_), do: Agent.start_link(fn -> %{blobs: %{}, head: nil} end, name: __MODULE__)

    def reset, do: Agent.update(__MODULE__, fn _ -> %{blobs: %{}, head: nil} end)

    def succeed_then_fail(n) when is_integer(n) and n >= 0 do
      Agent.update(__MODULE__, fn s -> Map.put(s, :succeeds_left, n) end)
    end
  end

  defmodule FakeIPFS do
    def ping, do: :ok

    def add_json(map) do
      Agent.get_and_update(Store, fn s ->
        case Map.get(s, :succeeds_left) do
          0 ->
            {{:error, :injected_failure}, Map.delete(s, :succeeds_left)}

          n when is_integer(n) and n > 0 ->
            cid = "bafy" <> Integer.to_string(System.unique_integer([:positive]))
            {{:ok, cid}, %{s | blobs: Map.put(s.blobs, cid, map), succeeds_left: n - 1}}

          _ ->
            cid = "bafy" <> Integer.to_string(System.unique_integer([:positive]))
            {{:ok, cid}, %{s | blobs: Map.put(s.blobs, cid, map)}}
        end
      end)
    end

    def cat_json(cid) do
      case Agent.get(Store, &Map.get(&1.blobs, cid)) do
        nil -> {:error, :not_found}
        map -> {:ok, map}
      end
    end
  end

  defmodule UnconfiguredIdentity do
    def configured?, do: false
  end

  def tmp_dir do
    dir = Path.join(System.tmp_dir!(), "concrete-cot-#{System.unique_integer([:positive])}")
    File.rm_rf!(dir)
    File.mkdir_p!(dir)
    dir
  end

  def put_fakes do
    Application.put_env(:concrete_runtime, :ipfs, FakeIPFS)
    Application.put_env(:concrete_runtime, :iota_identity, UnconfiguredIdentity)
  end

  def clear_fakes do
    Application.delete_env(:concrete_runtime, :ipfs)
    Application.delete_env(:concrete_runtime, :iota_identity)
    Application.delete_env(:concrete_runtime, :user_identity)
  end

  def helen_attrs do
    %{
      username: "Helen",
      public_key: "mldsa87:helen-test-pk",
      private_key: "helen-paper-sk",
      pin: "12345"
    }
  end

  def alice_attrs do
    %{
      username: "Alice",
      public_key: "mldsa87:alice-test-pk",
      private_key: "alice-paper-sk"
    }
  end

  def children(dir) do
    [
      {ConcreteRuntime.Lab, data_dir: dir},
      {Registry, keys: :unique, name: ConcreteRuntime.VaultRegistry},
      {ConcreteRuntime.NodeSupervisor, []},
      {ConcreteRuntime.Bootstrap, data_dir: dir},
      {ConcreteRuntime.InfoObjects, data_dir: dir},
      {ConcreteRuntime.UserDirectory, data_dir: dir},
      {ConcreteRuntime.DataObjects, data_dir: dir},
      {ConcreteRuntime.Session, []},
      {ConcreteRuntime.Workspaces, data_dir: dir}
    ]
  end
end
