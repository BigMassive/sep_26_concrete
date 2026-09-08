defmodule ConcreteRuntime.IPFS do
  @moduledoc """
  Typed HTTP client for the lab Kubo node (ADR 0002 stand-in).
  """

  @default_base "http://127.0.0.1:5001"

  def base_url do
    System.get_env("CONCRETE_IPFS_API") || @default_base
  end

  @doc "Add raw binary/string content; returns CID (Hash)."
  def add(content) when is_binary(content) do
    url = base_url() <> "/api/v0/add"

    case Req.post(url,
           form_multipart: [
             file: {content, filename: "blob.json", content_type: "application/json"}
           ]
         ) do
      {:ok, %{status: 200, body: body}} when is_map(body) ->
        {:ok, body["Hash"]}

      {:ok, %{status: 200, body: body}} when is_binary(body) ->
        line = body |> String.split("\n", trim: true) |> List.first()

        case Jason.decode(line || "") do
          {:ok, %{"Hash" => hash}} -> {:ok, hash}
          _ -> {:error, {:ipfs_add_decode, body}}
        end

      {:ok, resp} ->
        {:error, {:ipfs_add_http, resp.status, resp.body}}

      {:error, reason} ->
        {:error, {:ipfs_add, reason}}
    end
  end

  def add_json(map) when is_map(map) do
    add(Jason.encode!(map))
  end

  def cat(cid) when is_binary(cid) do
    url = base_url() <> "/api/v0/cat?arg=#{URI.encode(cid)}"

    case Req.post(url) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, body}

      {:ok, resp} ->
        {:error, {:ipfs_cat_http, resp.status, resp.body}}

      {:error, reason} ->
        {:error, {:ipfs_cat, reason}}
    end
  end

  def cat_json(cid) do
    with {:ok, body} <- cat(cid),
         {:ok, map} <- Jason.decode(body) do
      {:ok, map}
    else
      {:error, _} = err -> err
      {:ok, other} -> {:error, {:ipfs_cat_not_json, other}}
    end
  end

  def ping do
    url = base_url() <> "/api/v0/id"

    case Req.post(url) do
      {:ok, %{status: 200}} -> :ok
      {:ok, resp} -> {:error, {:ipfs_ping, resp.status}}
      {:error, reason} -> {:error, {:ipfs_ping, reason}}
    end
  end
end
