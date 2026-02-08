defmodule ADKExEcto.SessionServiceTest do
  use ExUnit.Case

  alias ADKExEcto.SessionService
  alias ADKExEcto.TestRepo, as: Repo
  alias ADK.Event
  alias ADK.Event.Actions
  alias ADK.Types.{Content, Part}

  setup do
    # Clean up tables between tests (in-memory SQLite, no sandbox)
    Repo.delete_all(ADKExEcto.Schemas.Event)
    Repo.delete_all(ADKExEcto.Schemas.Session)
    Repo.delete_all(ADKExEcto.Schemas.AppState)
    Repo.delete_all(ADKExEcto.Schemas.UserState)
    :ok
  end

  defp create_session(opts \\ []) do
    app = Keyword.get(opts, :app_name, "test_app")
    user = Keyword.get(opts, :user_id, "user1")
    sid = Keyword.get(opts, :session_id, UUID.uuid4())
    state = Keyword.get(opts, :state, %{})

    SessionService.create(Repo,
      app_name: app,
      user_id: user,
      session_id: sid,
      state: state
    )
  end

  defp make_event(opts \\ []) do
    Event.new(
      invocation_id: Keyword.get(opts, :invocation_id, UUID.uuid4()),
      author: Keyword.get(opts, :author, "test_agent"),
      content: Keyword.get(opts, :content, %Content{
        role: "model",
        parts: [%Part{text: Keyword.get(opts, :text, "hello")}]
      }),
      actions: Keyword.get(opts, :actions, %Actions{
        state_delta: Keyword.get(opts, :state_delta, %{})
      })
    )
  end

  describe "create" do
    test "stores session and returns struct with merged state" do
      {:ok, session} = create_session()

      assert session.app_name == "test_app"
      assert session.user_id == "user1"
      assert is_binary(session.id)
      assert session.events == []
      assert session.state == %{}
    end

    test "routes app:/user: state to separate tables" do
      {:ok, session} =
        create_session(
          state: %{
            "app:model" => "gpt-4",
            "user:pref" => "dark",
            "counter" => 0
          }
        )

      assert session.state["app:model"] == "gpt-4"
      assert session.state["user:pref"] == "dark"
      assert session.state["counter"] == 0
    end

    test "with explicit session_id" do
      {:ok, session} = create_session(session_id: "my-session")
      assert session.id == "my-session"
    end
  end

  describe "get" do
    test "returns merged state (session + app + user)" do
      {:ok, session} =
        create_session(
          state: %{
            "app:shared" => "yes",
            "user:name" => "Alice",
            "local" => "data"
          }
        )

      {:ok, fetched} =
        SessionService.get(Repo,
          app_name: "test_app",
          user_id: "user1",
          session_id: session.id
        )

      assert fetched.state["app:shared"] == "yes"
      assert fetched.state["user:name"] == "Alice"
      assert fetched.state["local"] == "data"
    end

    test "returns :not_found for missing session" do
      assert {:error, :not_found} =
               SessionService.get(Repo,
                 app_name: "nope",
                 user_id: "nope",
                 session_id: "nope"
               )
    end

    test "with num_recent_events limits returned events" do
      {:ok, session} = create_session()

      for i <- 1..5 do
        event = make_event(text: "msg #{i}")
        :ok = SessionService.append_event(Repo, session, event)
      end

      {:ok, fetched} =
        SessionService.get(Repo,
          app_name: "test_app",
          user_id: "user1",
          session_id: session.id,
          num_recent_events: 2
        )

      assert length(fetched.events) == 2
    end

    test "returns events in chronological order" do
      {:ok, session} = create_session()

      for i <- 1..3 do
        event = make_event(text: "msg #{i}")
        :ok = SessionService.append_event(Repo, session, event)
      end

      {:ok, fetched} =
        SessionService.get(Repo,
          app_name: "test_app",
          user_id: "user1",
          session_id: session.id
        )

      texts =
        Enum.map(fetched.events, fn e ->
          hd(e.content.parts).text
        end)

      assert texts == ["msg 1", "msg 2", "msg 3"]
    end
  end

  describe "list" do
    test "by app_name and user_id" do
      {:ok, _s1} = create_session(session_id: "s1")
      {:ok, _s2} = create_session(session_id: "s2")

      {:ok, sessions} =
        SessionService.list(Repo, app_name: "test_app", user_id: "user1")

      assert length(sessions) == 2
      ids = Enum.map(sessions, & &1.id) |> Enum.sort()
      assert ids == ["s1", "s2"]
    end

    test "different user sees no sessions" do
      {:ok, _} = create_session()

      {:ok, sessions} =
        SessionService.list(Repo, app_name: "test_app", user_id: "other_user")

      assert sessions == []
    end
  end

  describe "delete" do
    test "removes session and events" do
      {:ok, session} = create_session()
      event = make_event()
      :ok = SessionService.append_event(Repo, session, event)

      :ok =
        SessionService.delete(Repo,
          app_name: "test_app",
          user_id: "user1",
          session_id: session.id
        )

      assert {:error, :not_found} =
               SessionService.get(Repo,
                 app_name: "test_app",
                 user_id: "user1",
                 session_id: session.id
               )
    end
  end

  describe "append_event" do
    test "persists event" do
      {:ok, session} = create_session()
      event = make_event(text: "stored message")
      :ok = SessionService.append_event(Repo, session, event)

      {:ok, fetched} =
        SessionService.get(Repo,
          app_name: "test_app",
          user_id: "user1",
          session_id: session.id
        )

      assert length(fetched.events) == 1
      [e] = fetched.events
      assert hd(e.content.parts).text == "stored message"
    end

    test "routes state_delta prefixes correctly" do
      {:ok, session} = create_session()

      event =
        make_event(
          state_delta: %{
            "app:global_key" => "global_val",
            "user:user_key" => "user_val",
            "session_key" => "session_val"
          }
        )

      :ok = SessionService.append_event(Repo, session, event)

      {:ok, fetched} =
        SessionService.get(Repo,
          app_name: "test_app",
          user_id: "user1",
          session_id: session.id
        )

      assert fetched.state["app:global_key"] == "global_val"
      assert fetched.state["user:user_key"] == "user_val"
      assert fetched.state["session_key"] == "session_val"
    end

    test "discards temp: keys" do
      {:ok, session} = create_session()

      event =
        make_event(
          state_delta: %{
            "temp:scratch" => "gone",
            "keep" => "this"
          }
        )

      :ok = SessionService.append_event(Repo, session, event)

      {:ok, fetched} =
        SessionService.get(Repo,
          app_name: "test_app",
          user_id: "user1",
          session_id: session.id
        )

      assert fetched.state["keep"] == "this"
      refute Map.has_key?(fetched.state, "temp:scratch")
    end

    test "updates updated_at" do
      {:ok, session} = create_session()
      original_time = session.last_update_time

      Process.sleep(10)
      event = make_event()
      :ok = SessionService.append_event(Repo, session, event)

      {:ok, fetched} =
        SessionService.get(Repo,
          app_name: "test_app",
          user_id: "user1",
          session_id: session.id
        )

      assert DateTime.compare(fetched.last_update_time, original_time) != :lt
    end

    test "skips partial events" do
      {:ok, session} = create_session()

      partial_event = %{make_event() | partial: true}
      :ok = SessionService.append_event(Repo, session, partial_event)

      {:ok, fetched} =
        SessionService.get(Repo,
          app_name: "test_app",
          user_id: "user1",
          session_id: session.id
        )

      assert fetched.events == []
    end
  end

  describe "app_state shared across sessions" do
    test "app state visible in all sessions for same app" do
      {:ok, s1} = create_session(session_id: "s1")
      {:ok, _s2} = create_session(session_id: "s2")

      event = make_event(state_delta: %{"app:shared" => "value"})
      :ok = SessionService.append_event(Repo, s1, event)

      {:ok, fetched_s2} =
        SessionService.get(Repo,
          app_name: "test_app",
          user_id: "user1",
          session_id: "s2"
        )

      assert fetched_s2.state["app:shared"] == "value"
    end
  end

  describe "user_state shared across user sessions" do
    test "user state visible in user's sessions" do
      {:ok, s1} = create_session(session_id: "s1")
      {:ok, _s2} = create_session(session_id: "s2")

      event = make_event(state_delta: %{"user:pref" => "dark"})
      :ok = SessionService.append_event(Repo, s1, event)

      {:ok, fetched_s2} =
        SessionService.get(Repo,
          app_name: "test_app",
          user_id: "user1",
          session_id: "s2"
        )

      assert fetched_s2.state["user:pref"] == "dark"
    end
  end

  describe "empty state maps" do
    test "serialize correctly (not null)" do
      {:ok, session} = create_session(state: %{})

      {:ok, fetched} =
        SessionService.get(Repo,
          app_name: "test_app",
          user_id: "user1",
          session_id: session.id
        )

      assert fetched.state == %{}
    end
  end

  describe "JSON round-trip" do
    test "Content and Actions structs survive serialization" do
      {:ok, session} = create_session()

      content = %Content{
        role: "model",
        parts: [
          %Part{text: "hello world"},
          %Part{
            function_call: %ADK.Types.FunctionCall{
              name: "my_tool",
              id: "fc1",
              args: %{"key" => "value"}
            }
          }
        ]
      }

      event =
        make_event(
          content: content,
          state_delta: %{"app:x" => 1, "user:y" => 2, "z" => 3}
        )

      :ok = SessionService.append_event(Repo, session, event)

      {:ok, fetched} =
        SessionService.get(Repo,
          app_name: "test_app",
          user_id: "user1",
          session_id: session.id
        )

      [e] = fetched.events
      assert e.content.role == "model"
      assert length(e.content.parts) == 2
      [text_part, fc_part] = e.content.parts
      assert text_part.text == "hello world"
      assert fc_part.function_call.name == "my_tool"
      assert fc_part.function_call.args == %{"key" => "value"}
    end
  end

  describe "full create->append->get cycle" do
    test "end-to-end with SQLite" do
      {:ok, session} =
        create_session(
          state: %{"app:model" => "gpt-4", "counter" => 0}
        )

      # Append a user event
      user_event =
        make_event(
          author: "user",
          text: "Hello!",
          state_delta: %{}
        )

      :ok = SessionService.append_event(Repo, session, user_event)

      # Append an agent event with state changes
      agent_event =
        make_event(
          author: "agent",
          text: "Hi there!",
          state_delta: %{
            "counter" => 1,
            "user:last_seen" => "now",
            "temp:scratch" => "ignored"
          }
        )

      :ok = SessionService.append_event(Repo, session, agent_event)

      # Fetch and verify
      {:ok, fetched} =
        SessionService.get(Repo,
          app_name: "test_app",
          user_id: "user1",
          session_id: session.id
        )

      assert length(fetched.events) == 2
      assert fetched.state["app:model"] == "gpt-4"
      assert fetched.state["counter"] == 1
      assert fetched.state["user:last_seen"] == "now"
      refute Map.has_key?(fetched.state, "temp:scratch")
    end
  end

  describe "migration creates tables" do
    test "all 4 tables exist with correct columns" do
      # If we got this far, migration worked — verify by querying
      assert Repo.all(ADKExEcto.Schemas.Session) == []
      assert Repo.all(ADKExEcto.Schemas.Event) == []
      assert Repo.all(ADKExEcto.Schemas.AppState) == []
      assert Repo.all(ADKExEcto.Schemas.UserState) == []
    end
  end
end
