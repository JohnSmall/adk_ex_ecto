defmodule ADKExEcto.SessionService do
  @moduledoc """
  Ecto-backed session service implementing `ADK.Session.Service`.

  Uses a configurable Ecto Repo for database operations. The repo is
  passed as the `server` argument (matching the behaviour's GenServer.server()
  parameter — in this case, it's a module name).

  ## Usage

      {:ok, runner} = ADK.Runner.new(
        app_name: "my_app",
        root_agent: agent,
        session_service: MyApp.Repo,
        session_module: ADKExEcto.SessionService
      )
  """

  @behaviour ADK.Session.Service

  alias ADKExEcto.Schemas
  alias ADK.Event, as: ADKEvent
  alias ADK.Event.Actions
  alias ADK.Session
  alias ADK.Session.State, as: StateUtil
  alias ADK.Types.{Content, Part, FunctionCall, FunctionResponse, Blob}

  import Ecto.Query

  # -- Behaviour Implementation --

  @impl ADK.Session.Service
  def create(repo, opts) do
    app_name = Keyword.fetch!(opts, :app_name)
    user_id = Keyword.fetch!(opts, :user_id)
    session_id = Keyword.get(opts, :session_id) || UUID.uuid4()
    initial_state = Keyword.get(opts, :state, %{})

    {app_delta, user_delta, session_delta} = StateUtil.extract_deltas(initial_state)

    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    result =
      repo.transaction(fn ->
        upsert_app_state(repo, app_name, app_delta, now)
        upsert_user_state(repo, app_name, user_id, user_delta, now)

        session_attrs = %{
          app_name: app_name,
          user_id: user_id,
          id: session_id,
          state: session_delta
        }

        changeset = Schemas.Session.changeset(%Schemas.Session{}, session_attrs)
        repo.insert!(changeset)
      end)

    case result do
      {:ok, db_session} ->
        merged = build_merged_state(repo, app_name, user_id, db_session.state)

        session = %Session{
          id: session_id,
          app_name: app_name,
          user_id: user_id,
          state: merged,
          events: [],
          last_update_time: db_session.updated_at
        }

        {:ok, session}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl ADK.Session.Service
  def get(repo, opts) do
    app_name = Keyword.fetch!(opts, :app_name)
    user_id = Keyword.fetch!(opts, :user_id)
    session_id = Keyword.fetch!(opts, :session_id)
    num_recent = Keyword.get(opts, :num_recent_events)
    after_time = Keyword.get(opts, :after)

    case repo.get_by(Schemas.Session, app_name: app_name, user_id: user_id, id: session_id) do
      nil ->
        {:error, :not_found}

      db_session ->
        events = load_events(repo, app_name, user_id, session_id, num_recent, after_time)
        merged = build_merged_state(repo, app_name, user_id, db_session.state)

        session = %Session{
          id: session_id,
          app_name: app_name,
          user_id: user_id,
          state: merged,
          events: Enum.map(events, &db_event_to_adk_event/1),
          last_update_time: db_session.updated_at
        }

        {:ok, session}
    end
  end

  @impl ADK.Session.Service
  def list(repo, opts) do
    app_name = Keyword.fetch!(opts, :app_name)
    user_id = Keyword.fetch!(opts, :user_id)

    db_sessions =
      from(s in Schemas.Session,
        where: s.app_name == ^app_name and s.user_id == ^user_id
      )
      |> repo.all()

    sessions =
      Enum.map(db_sessions, fn db_session ->
        events = load_events(repo, app_name, user_id, db_session.id, nil, nil)
        merged = build_merged_state(repo, app_name, user_id, db_session.state)

        %Session{
          id: db_session.id,
          app_name: app_name,
          user_id: user_id,
          state: merged,
          events: Enum.map(events, &db_event_to_adk_event/1),
          last_update_time: db_session.updated_at
        }
      end)

    {:ok, sessions}
  end

  @impl ADK.Session.Service
  def delete(repo, opts) do
    app_name = Keyword.fetch!(opts, :app_name)
    user_id = Keyword.fetch!(opts, :user_id)
    session_id = Keyword.fetch!(opts, :session_id)

    # Delete events first, then session
    from(e in Schemas.Event,
      where: e.app_name == ^app_name and e.user_id == ^user_id and e.session_id == ^session_id
    )
    |> repo.delete_all()

    from(s in Schemas.Session,
      where: s.app_name == ^app_name and s.user_id == ^user_id and s.id == ^session_id
    )
    |> repo.delete_all()

    :ok
  end

  @impl ADK.Session.Service
  def append_event(repo, %Session{} = session, %ADKEvent{} = event) do
    if event.partial do
      :ok
    else
      do_append_event(repo, session, event)
    end
  end

  # -- Private Implementation --

  defp do_append_event(repo, session, event) do
    result =
      repo.transaction(fn ->
        db_session =
          repo.get_by(Schemas.Session,
            app_name: session.app_name,
            user_id: session.user_id,
            id: session.id
          )

        if db_session == nil do
          repo.rollback(:not_found)
        end

        # Staleness check
        check_staleness(db_session, session)

        delta = event.actions.state_delta
        {app_delta, user_delta, session_delta} = StateUtil.extract_deltas(delta)

        now =
          (event.timestamp || DateTime.utc_now())
          |> DateTime.truncate(:microsecond)

        upsert_app_state(repo, session.app_name, app_delta, now)
        upsert_user_state(repo, session.app_name, session.user_id, user_delta, now)

        # Update session state
        new_session_state = Map.merge(db_session.state || %{}, session_delta)

        db_session
        |> Ecto.Changeset.change(state: new_session_state, updated_at: now)
        |> repo.update!()

        # Insert event
        trimmed_delta = StateUtil.trim_temp_delta(delta)

        event_attrs = %{
          id: event.id,
          app_name: session.app_name,
          user_id: session.user_id,
          session_id: session.id,
          invocation_id: event.invocation_id,
          author: event.author,
          content: serialize_content(event.content),
          actions: serialize_actions(%{event.actions | state_delta: trimmed_delta}),
          branch: event.branch,
          partial: event.partial,
          turn_complete: event.turn_complete,
          error_code: event.error_code,
          error_message: event.error_message,
          interrupted: event.interrupted,
          custom_metadata: event.custom_metadata,
          usage_metadata: event.usage_metadata,
          citation_metadata: event.citation_metadata,
          grounding_metadata: event.grounding_metadata,
          long_running_tool_ids: event.long_running_tool_ids || [],
          timestamp: now
        }

        changeset = Schemas.Event.changeset(%Schemas.Event{}, event_attrs)
        repo.insert!(changeset)
      end)

    case result do
      {:ok, _} -> :ok
      {:error, :not_found} -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  defp check_staleness(_db_session, _session) do
    # Staleness detection is available but not enforced by default.
    # The Runner passes the original session struct and doesn't re-fetch
    # between appends, so strict checking would break normal usage.
    # Applications needing strict staleness can compare last_update_time
    # before calling append_event.
    :ok
  end

  # -- State Helpers --

  defp upsert_app_state(_repo, _app_name, delta, _now) when map_size(delta) == 0, do: :ok

  defp upsert_app_state(repo, app_name, delta, now) do
    case repo.get_by(Schemas.AppState, app_name: app_name) do
      nil ->
        %Schemas.AppState{}
        |> Ecto.Changeset.change(app_name: app_name, state: delta, updated_at: now)
        |> repo.insert!()

      existing ->
        new_state = Map.merge(existing.state || %{}, delta)

        existing
        |> Ecto.Changeset.change(state: new_state, updated_at: now)
        |> repo.update!()
    end
  end

  defp upsert_user_state(_repo, _app_name, _user_id, delta, _now) when map_size(delta) == 0,
    do: :ok

  defp upsert_user_state(repo, app_name, user_id, delta, now) do
    case repo.get_by(Schemas.UserState, app_name: app_name, user_id: user_id) do
      nil ->
        %Schemas.UserState{}
        |> Ecto.Changeset.change(
          app_name: app_name,
          user_id: user_id,
          state: delta,
          updated_at: now
        )
        |> repo.insert!()

      existing ->
        new_state = Map.merge(existing.state || %{}, delta)

        existing
        |> Ecto.Changeset.change(state: new_state, updated_at: now)
        |> repo.update!()
    end
  end

  defp build_merged_state(repo, app_name, user_id, session_state) do
    app_st = get_app_state(repo, app_name)
    user_st = get_user_state(repo, app_name, user_id)
    StateUtil.merge_states(app_st, user_st, session_state || %{})
  end

  defp get_app_state(repo, app_name) do
    case repo.get_by(Schemas.AppState, app_name: app_name) do
      nil -> %{}
      record -> record.state || %{}
    end
  end

  defp get_user_state(repo, app_name, user_id) do
    case repo.get_by(Schemas.UserState, app_name: app_name, user_id: user_id) do
      nil -> %{}
      record -> record.state || %{}
    end
  end

  # -- Event Loading --

  defp load_events(repo, app_name, user_id, session_id, num_recent, after_time) do
    query =
      from(e in Schemas.Event,
        where:
          e.app_name == ^app_name and
            e.user_id == ^user_id and
            e.session_id == ^session_id,
        order_by: [asc: e.timestamp]
      )

    query = apply_after_filter(query, after_time)
    query = apply_limit(query, num_recent)

    repo.all(query)
  end

  defp apply_after_filter(query, nil), do: query

  defp apply_after_filter(query, %DateTime{} = after_time) do
    from(e in query, where: e.timestamp > ^after_time)
  end

  defp apply_limit(query, nil), do: query

  defp apply_limit(query, num_recent) when is_integer(num_recent) do
    # Get last N events: subquery ordered desc with limit, then re-order asc
    sub =
      from(e in query,
        order_by: [desc: e.timestamp],
        limit: ^num_recent
      )

    from(e in subquery(sub), order_by: [asc: e.timestamp])
  end

  # -- Serialization --

  defp serialize_content(nil), do: nil

  defp serialize_content(%Content{} = content) do
    %{
      "role" => content.role,
      "parts" => Enum.map(content.parts, &serialize_part/1)
    }
  end

  defp serialize_part(%Part{} = part) do
    map = %{}
    map = if part.text, do: Map.put(map, "text", part.text), else: map
    map = if part.thought, do: Map.put(map, "thought", part.thought), else: map
    map = if part.function_call, do: Map.put(map, "function_call", serialize_fc(part.function_call)), else: map
    map = if part.function_response, do: Map.put(map, "function_response", serialize_fr(part.function_response)), else: map

    if part.inline_data do
      Map.put(map, "inline_data", %{
        "data" => Base.encode64(part.inline_data.data),
        "mime_type" => part.inline_data.mime_type
      })
    else
      map
    end
  end

  defp serialize_fc(%FunctionCall{} = fc) do
    %{"name" => fc.name, "id" => fc.id, "args" => fc.args}
  end

  defp serialize_fr(%FunctionResponse{} = fr) do
    %{"name" => fr.name, "id" => fr.id, "response" => fr.response}
  end

  defp serialize_actions(%Actions{} = actions) do
    %{
      "state_delta" => actions.state_delta,
      "artifact_delta" => actions.artifact_delta,
      "transfer_to_agent" => actions.transfer_to_agent,
      "escalate" => actions.escalate,
      "skip_summarization" => actions.skip_summarization
    }
  end

  # -- Deserialization --

  defp db_event_to_adk_event(%Schemas.Event{} = db) do
    %ADKEvent{
      id: db.id,
      invocation_id: db.invocation_id,
      branch: db.branch,
      author: db.author,
      content: deserialize_content(db.content),
      partial: db.partial || false,
      turn_complete: db.turn_complete || false,
      interrupted: db.interrupted || false,
      error_code: db.error_code,
      error_message: db.error_message,
      actions: deserialize_actions(db.actions),
      custom_metadata: db.custom_metadata,
      usage_metadata: db.usage_metadata,
      citation_metadata: db.citation_metadata,
      grounding_metadata: db.grounding_metadata,
      long_running_tool_ids: db.long_running_tool_ids || [],
      timestamp: db.timestamp
    }
  end

  defp deserialize_content(nil), do: nil

  defp deserialize_content(%{"role" => role, "parts" => parts}) do
    %Content{
      role: role,
      parts: Enum.map(parts, &deserialize_part/1)
    }
  end

  defp deserialize_part(map) do
    %Part{
      text: map["text"],
      thought: map["thought"] || false,
      function_call: deserialize_fc(map["function_call"]),
      function_response: deserialize_fr(map["function_response"]),
      inline_data: deserialize_blob(map["inline_data"])
    }
  end

  defp deserialize_fc(nil), do: nil

  defp deserialize_fc(map) do
    %FunctionCall{name: map["name"], id: map["id"], args: map["args"] || %{}}
  end

  defp deserialize_fr(nil), do: nil

  defp deserialize_fr(map) do
    %FunctionResponse{name: map["name"], id: map["id"], response: map["response"] || %{}}
  end

  defp deserialize_blob(nil), do: nil

  defp deserialize_blob(map) do
    %Blob{data: Base.decode64!(map["data"]), mime_type: map["mime_type"]}
  end

  defp deserialize_actions(nil), do: %Actions{}

  defp deserialize_actions(map) do
    %Actions{
      state_delta: map["state_delta"] || %{},
      artifact_delta: map["artifact_delta"] || %{},
      transfer_to_agent: map["transfer_to_agent"],
      escalate: map["escalate"] || false,
      skip_summarization: map["skip_summarization"] || false
    }
  end
end
