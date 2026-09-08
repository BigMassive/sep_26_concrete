defmodule ConcreteRuntime.Iota do
  @moduledoc """
  Lab IOTA localnet client (ADR 0002). Beat 2 records an RPC checkpoint anchor
  alongside DID/IPFS; full IOTA Identity document publish can harden later.
  """

  @default_rpc "http://127.0.0.1:9000"

  def rpc_url do
    System.get_env("CONCRETE_IOTA_RPC") || @default_rpc
  end

  def ping do
    case rpc("iota_getLatestCheckpointSequenceNumber", []) do
      {:ok, _} -> :ok
      err -> err
    end
  end

  def latest_checkpoint do
    rpc("iota_getLatestCheckpointSequenceNumber", [])
  end

  def chain_identifier do
    rpc("iota_getChainIdentifier", [])
  end

  def get_object(object_id) when is_binary(object_id) do
    case rpc("iota_getObject", [
           object_id,
           %{"showContent" => true, "showType" => true, "showOwner" => true}
         ]) do
      {:ok, %{"data" => data}} when is_map(data) -> {:ok, data}
      {:ok, other} -> {:error, {:iota_object, other}}
      err -> err
    end
  end

  defp rpc(method, params) do
    body = %{jsonrpc: "2.0", id: 1, method: method, params: params}

    case Req.post(rpc_url(), json: body) do
      {:ok, %{status: 200, body: %{"result" => result}}} ->
        {:ok, result}

      {:ok, %{status: 200, body: body}} when is_binary(body) ->
        case Jason.decode(body) do
          {:ok, %{"result" => result}} -> {:ok, result}
          {:ok, %{"error" => err}} -> {:error, {:iota_rpc, err}}
          other -> {:error, {:iota_rpc_decode, other}}
        end

      {:ok, %{status: 200, body: %{"error" => err}}} ->
        {:error, {:iota_rpc, err}}

      {:ok, resp} ->
        {:error, {:iota_http, resp.status, resp.body}}

      {:error, reason} ->
        {:error, {:iota_http, reason}}
    end
  end
end
