defmodule ConcreteRuntime.BootstrapTest do
  use ExUnit.Case, async: false

  defmodule FakeIssuer do
    def onboard("King") do
      {:ok,
       %{
         id: "mldsa87:king-test-pk",
         public_key: "mldsa87:king-test-pk",
         display_name: "King",
         index: 0
       }}
    end

    def onboard("Eve") do
      {:ok,
       %{
         id: "mldsa87:eve-test-pk",
         public_key: "mldsa87:eve-test-pk",
         display_name: "Eve",
         index: 0
       }}
    end

    def onboard(name) do
      id = "mldsa87:" <> name
      {:ok, %{id: id, public_key: id, display_name: name, index: 0}}
    end
  end

  setup do
    Application.put_env(:concrete_runtime, :user_identity, FakeIssuer)

    on_exit(fn ->
      Application.delete_env(:concrete_runtime, :user_identity)
    end)

    dir = Path.join(System.tmp_dir!(), "concrete-bootstrap-#{System.unique_integer([:positive])}")
    File.rm_rf!(dir)
    File.mkdir_p!(dir)

    start_supervised!({ConcreteRuntime.Bootstrap, data_dir: dir})
    %{dir: dir}
  end

  test "first boot mints bootstrap cap to King's ML-DSA-87 public key" do
    status = ConcreteRuntime.Bootstrap.status()
    assert status.node_id == "node-1"
    assert status.king.display_name == "King"
    assert status.king.id == "mldsa87:king-test-pk"
    assert status.bootstrap_capability.meaning == "bootstrap/do-anything"
    assert status.bootstrap_capability.holder_principal_id == status.king.id

    assert {:ok, :allowed, _} = ConcreteRuntime.Bootstrap.authorize(status.king.id, "mutate")
  end

  test "second principal is denied" do
    {:ok, eve} = ConcreteRuntime.Bootstrap.ensure_principal("Eve")
    assert eve.id == "mldsa87:eve-test-pk"
    assert {:error, :capability_denied} = ConcreteRuntime.Bootstrap.authorize(eve.id, "mutate")
  end

  test "state persists across process restart", %{dir: dir} do
    status1 = ConcreteRuntime.Bootstrap.status()
    king_id = status1.king.id

    stop_supervised!(ConcreteRuntime.Bootstrap)
    start_supervised!({ConcreteRuntime.Bootstrap, data_dir: dir})

    status2 = ConcreteRuntime.Bootstrap.status()
    assert status2.king.id == king_id
    assert {:ok, :allowed, _} = ConcreteRuntime.Bootstrap.authorize(king_id, "mutate")
  end
end
