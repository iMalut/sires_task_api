defmodule SiresTaskApiWeb.Swagger.Projects do
  use PhoenixSwagger

  def swagger_definitions do
    %{
      Project:
        swagger_schema do
          title("Project")

          properties do
            name(:string, "Name", required: true)
          end
        end
    }
  end

  swagger_path :create do
    post("/projects")
    tag("Projects")
    summary("Create a project")

    parameters do
      body(
        :body,
        Schema.new do
          properties do
            project(Schema.ref(:Project), "Project properties", required: true)
          end
        end,
        "Body",
        required: true
      )
    end

    response(201, "Created")
    response(400, "Bad Request")
    response(401, "Unauthorized")
    response(422, "Unprocessable Entity")
  end
end