defmodule SiresTaskApiWeb.TaskEndpointTest do
  use SiresTaskApiWeb.ConnCase, async: true

  describe "GET /api/v1/tasks" do
    setup %{conn: conn} do
      user = insert!(:user)
      task = insert!(:task)
      {:ok, user: user, conn: conn |> sign_as(user), task: task}
    end

    test "show task", ctx do
      insert!(:project_member, user: ctx.user, project: ctx.task.project, role: "guest")
      response = ctx.conn |> get("/api/v1/tasks/#{ctx.task.id}") |> json_response(200)
      assert response["task"]["id"] == ctx.task.id
    end

    test "show task for global admin", ctx do
      admin = insert!(:admin)
      conn = ctx.conn |> sign_as(admin)
      response = conn |> get("/api/v1/tasks/#{ctx.task.id}") |> json_response(200)
      assert response["task"]["id"] == ctx.task.id
    end

    test "fail to show task without permissions", ctx do
      ctx.conn |> get("/api/v1/tasks/#{ctx.task.id}") |> json_response(403)
    end

    test "fail to show missing task", ctx do
      ctx.conn |> get("/api/v1/tasks/9999999999") |> json_response(404)
    end
  end

  describe "POST /api/v1/tasks" do
    test "create task", ctx do
      user = insert!(:user)
      project = insert!(:project)
      insert!(:project_member, user: user, project: project)
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      params = %{
        project_id: project.id,
        name: "Some task",
        description: "Do something",
        start_time: now |> DateTime.to_iso8601(),
        finish_time: now |> DateTime.add(1) |> DateTime.to_iso8601()
      }

      response =
        ctx.conn
        |> sign_as(user)
        |> post("/api/v1/tasks", task: params)
        |> json_response(201)

      assert response["task"]["project"]["id"] == project.id
      assert response["task"]["name"] == "Some task"
      assert response["task"]["description"] == "Do something"
      assert response["task"]["start_time"] == params.start_time
      assert response["task"]["finish_time"] == params.finish_time
    end

    test "fail to create task as guest", ctx do
      user = insert!(:user)
      project = insert!(:project)
      insert!(:project_member, user: user, project: project, role: "guest")

      ctx.conn
      |> sign_as(user)
      |> post("/api/v1/tasks", task: %{project_id: project.id, name: "Some task"})
      |> json_response(403)
    end

    test "fail to create task in a missing project", ctx do
      user = insert!(:user)

      ctx.conn
      |> sign_as(user)
      |> post("/api/v1/tasks", task: %{project_id: 9_999_999_999, name: "Some task"})
      |> json_response(404)
    end
  end

  describe "PUT /api/v1/tasks" do
    test "update task", ctx do
      user = insert!(:user)
      task = insert!(:task)
      insert!(:project_member, user: user, project: task.project)
      insert!(:task_member, user: user, task: task, role: "assignor")

      params = %{
        name: "New name",
        description: "New description",
        start_time: task.start_time |> DateTime.add(3600) |> DateTime.to_iso8601(),
        finish_time: task.finish_time |> DateTime.add(3600) |> DateTime.to_iso8601()
      }

      response =
        ctx.conn
        |> sign_as(user)
        |> put("/api/v1/tasks/#{task.id}", task: params)
        |> json_response(200)

      assert response["task"]["name"] == params.name
      assert response["task"]["description"] == params.description
      assert response["task"]["start_time"] == params.start_time
      assert response["task"]["finish_time"] == params.finish_time
    end

    test "update task as project admin", ctx do
      user = insert!(:user)
      task = insert!(:task)
      insert!(:project_member, user: user, project: task.project, role: "admin")

      ctx.conn
      |> sign_as(user)
      |> put("/api/v1/tasks/#{task.id}", task: %{description: "New description"})
      |> json_response(200)
    end

    test "update task as global admin", ctx do
      admin = insert!(:admin)
      task = insert!(:task)

      ctx.conn
      |> sign_as(admin)
      |> put("/api/v1/tasks/#{task.id}", task: %{description: "New description"})
      |> json_response(200)
    end

    test "fail to update task without permissions", ctx do
      user = insert!(:user)
      task = insert!(:task)
      insert!(:project_member, user: user, project: task.project)

      ctx.conn
      |> sign_as(user)
      |> put("/api/v1/tasks/#{task.id}", task: %{description: "New description"})
      |> json_response(403)
    end

    test "fail to update task with wrong params", ctx do
      user = insert!(:user)
      task = insert!(:task)
      insert!(:project_member, user: user, project: task.project)
      insert!(:task_member, user: user, task: task, role: "assignor")

      ctx.conn
      |> sign_as(user)
      |> put("/api/v1/tasks/#{task.id}", task: %{start_time: "wrong"})
      |> json_response(422)
    end

    test "fail to update missing task", ctx do
      user = insert!(:user)

      ctx.conn
      |> sign_as(user)
      |> put("/api/v1/tasks/9999999999", task: %{description: "New description"})
      |> json_response(404)
    end
  end

  describe "POST /api/v1/tasks/:id/mark_(un)done" do
    defp toggle_done_on_and_off(conn, task) do
      conn
      |> post("/api/v1/tasks/#{task.id}/mark_done")
      |> json_response(200)
      |> get_in(~w(task done))
      |> assert()

      conn
      |> post("/api/v1/tasks/#{task.id}/mark_undone")
      |> json_response(200)
      |> get_in(~w(task done))
      |> refute()
    end

    test "toggle task done off and on as task responsible member", ctx do
      task = insert!(:task)
      user = insert!(:user)
      insert!(:project_member, project: task.project, user: user)
      insert!(:task_member, task: task, user: user, role: "responsible")
      ctx.conn |> sign_as(user) |> toggle_done_on_and_off(task)
    end

    test "toggle task done off and on as task co-responsible member", ctx do
      task = insert!(:task)
      user = insert!(:user)
      insert!(:project_member, project: task.project, user: user)
      insert!(:task_member, task: task, user: user, role: "co-responsible")
      ctx.conn |> sign_as(user) |> toggle_done_on_and_off(task)
    end

    test "toggle task done off and on as task assignor", ctx do
      task = insert!(:task)
      user = insert!(:user)
      insert!(:project_member, project: task.project, user: user)
      insert!(:task_member, task: task, user: user, role: "assignor")
      ctx.conn |> sign_as(user) |> toggle_done_on_and_off(task)
    end

    test "toggle task done off and on as project admin", ctx do
      task = insert!(:task)
      user = insert!(:user)
      insert!(:project_member, project: task.project, user: user, role: "admin")
      ctx.conn |> sign_as(user) |> toggle_done_on_and_off(task)
    end

    test "toggle task done off and on as global admin", ctx do
      task = insert!(:task)
      admin = insert!(:admin)
      ctx.conn |> sign_as(admin) |> toggle_done_on_and_off(task)
    end

    test "fail to mark task done without permission", ctx do
      task = insert!(:task)
      user = insert!(:user)

      ctx.conn
      |> sign_as(user)
      |> post("/api/v1/tasks/#{task.id}/mark_done")
      |> json_response(403)
    end

    test "fail to mark missing task done", ctx do
      user = insert!(:user)

      ctx.conn
      |> sign_as(user)
      |> post("/api/v1/tasks/9999999999/mark_done")
      |> json_response(404)
    end
  end

  describe "DELETE /api/v1/tasks/:id" do
    setup %{conn: conn} do
      user = insert!(:user)
      {:ok, user: user, conn: conn |> sign_as(user), task: insert!(:task)}
    end

    test "delete task as task assignor", ctx do
      insert!(:project_member, project: ctx.task.project, user: ctx.user)
      insert!(:task_member, task: ctx.task, user: ctx.user, role: "assignor")

      ctx.conn |> delete("/api/v1/tasks/#{ctx.task.id}") |> json_response(200)
      ctx.conn |> get("/api/v1/tasks/#{ctx.task.id}") |> json_response(404)
    end

    test "delete task as project admin", ctx do
      insert!(:project_member, project: ctx.task.project, user: ctx.user, role: "admin")

      ctx.conn |> delete("/api/v1/tasks/#{ctx.task.id}") |> json_response(200)
      ctx.conn |> get("/api/v1/tasks/#{ctx.task.id}") |> json_response(404)
    end

    test "delete task as global admin", ctx do
      admin = insert!(:admin)
      conn = ctx.conn |> sign_as(admin)

      conn |> delete("/api/v1/tasks/#{ctx.task.id}") |> json_response(200)
      conn |> get("/api/v1/tasks/#{ctx.task.id}") |> json_response(404)
    end

    test "fail to delete task without permissions", ctx do
      insert!(:project_member, project: ctx.task.project, user: ctx.user)
      ctx.conn |> delete("/api/v1/tasks/#{ctx.task.id}") |> json_response(403)
    end

    test "fail to delete missing task", ctx do
      ctx.conn |> delete("/api/v1/tasks/9999999999") |> json_response(404)
    end
  end
end