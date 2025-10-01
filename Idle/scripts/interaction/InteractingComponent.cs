using Godot;
using System;
using System.Collections.Generic;
using System.Linq;

public partial class InteractingComponent : Node3D
{
	private Label interact_label;
	private List<Area3D> current_interactions = new List<Area3D>();
	private bool can_interact = true;
	private Item selectedItem;
	private CharacterBody3d player;
	private Timer interactSpeed;

	[Export] public float interact_range = 3.0f;

	public override void _Ready()
	{
		interact_label = GetNode<Label>("CanvasLayer/InteractLabel");
		player = GetParent<CharacterBody3d>();
		interactSpeed = GetNode<Timer>("InteractSpeed");


		interactSpeed.WaitTime = player.interactSpeed;
		interactSpeed.OneShot = true; // Ensure the timer stops after timeout
	}

	public override void _Input(InputEvent @event)
	{
		if (!interactSpeed.IsStopped())
		{
			GD.Print("Timer running, cannot interact yet.");
			return;
		}
		if (@event.IsActionPressed("mouse_left_click") && can_interact)
		{
			if (current_interactions.Count > 0)
			{
				can_interact = false;
				interact_label.Hide();

				// Call interact on the first interactable object
				var interactable = current_interactions[0];
				var parent = interactable.GetParent();

				if (parent.HasMethod("interact"))
				{
					bool result = (bool)parent.Call("interact", player);
					GD.Print("Interact returned: ", result);
					if (result)
					{
						interactSpeed.Start(); // Start the timer to enforce interaction speed
											   // play animation
						player.playHarvestAnimation();
					}
				}

				can_interact = true;
			}
		}
	}

	public override void _Process(double delta)
	{
		if (current_interactions.Count > 0 && can_interact)
		{
			current_interactions = current_interactions
				.OrderBy(area => SortByNearest(area, this))
				.ToList();

			var nearestInteraction = current_interactions[0];

			// Check if it has the is_interactable property
			if (nearestInteraction.HasMethod("get") &&
				(bool)nearestInteraction.Call("get", "is_interactable"))
			{
				interact_label.Text = (string)nearestInteraction.Call("get", "interact_name");
				interact_label.Show();
			}
		}
		else
		{
			interact_label.Hide();
		}
	}

	private float SortByNearest(Area3D area1, Node3D area2)
	{
		float area1_dist = area1.GlobalPosition.DistanceTo(area2.GlobalPosition);
		float area2_dist = area2.GlobalPosition.DistanceTo(area1.GlobalPosition);
		return area1_dist - area2_dist;
	}

	private void _on_interact_range_area_entered(Area3D area)
	{
		current_interactions.Add(area);
	}

	private void _on_interact_range_area_exited(Area3D area)
	{
		current_interactions.Remove(area);
	}

	public void SetInteractSpeed(float speed)
	{
		interactSpeed.WaitTime = interactSpeed.WaitTime * speed;
	}
}
