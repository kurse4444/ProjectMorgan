using Godot;
using System;

public partial class Camera3d : Camera3D
{
	private Area3D mouseArea;
	private MeshInstance3D areaMesh;

	public override void _Ready()
	{
		// Get the Area3D node from the sibling InteractingComponent
		mouseArea = GetNode<Area3D>("../InteractingComponent/InteractRange");
	}

	public override void _Process(double delta)
	{
		Vector2 mousePos = GetViewport().GetMousePosition();
		Vector3 from = ProjectRayOrigin(mousePos);
		Vector3 to = from + ProjectRayNormal(mousePos) * 1000;

		var spaceState = GetWorld3D().DirectSpaceState;
		var result = spaceState.IntersectRay(new PhysicsRayQueryParameters3D
		{
			From = from,
			To = to,
			CollisionMask = uint.MaxValue
		});

		if (result.Count > 0)
		{
			Vector3 position = (Vector3)result["position"];
			mouseArea.GlobalPosition = position;
		}

		if (Input.IsActionJustPressed("mouse_left_click"))
		{
			if (result.Count > 0)
			{
				Vector3 position = (Vector3)result["position"];
				GD.Print("Clicked at: ", position);
				// You can add your logic here, e.g., move a character to 'position'
			}
		}
	}
}
