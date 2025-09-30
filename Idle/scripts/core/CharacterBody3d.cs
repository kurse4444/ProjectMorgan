using Godot;
using System;

public partial class CharacterBody3d : CharacterBody3D
{
	[Signal]
	public delegate void PlantEventHandler();

	[Export]
	public float interactSpeed = 0.9f;
	[Export]
	public float Speed = 3.0f;
	[Export]
	public float TurnSpeed = 8.0f; // Speed of rotation in radians per second
	public const float MaxStepHeight = 1f;

	public AnimationPlayer animationPlayer;

	public bool canMove = true;

	public CanvasLayer canvasLayer;
	[Export]
	public float JumpVelocity = 4f;

	public override void _Ready()
	{
		// Configure step climbing properties
		FloorSnapLength = 0.4f;
		FloorMaxAngle = Mathf.DegToRad(60.0f);
		FloorStopOnSlope = false; // Allows sliding up slopes/steps

		canvasLayer = GetNode<CanvasLayer>("CanvasLayer");

		// Safely get the AnimationPlayer node
		var animPlayerNode = GetNodeOrNull<AnimationPlayer>("AnimationPlayer");
		if (animPlayerNode != null)
		{
			animationPlayer = animPlayerNode;
		}
		else
		{
			GD.PrintErr("AnimationPlayer node not found. Animation will be disabled.");
		}

		DisableInput();
	}

	public override void _PhysicsProcess(double delta)
	{

		Vector3 velocity = Velocity;

		// Add the gravity.
		if (!IsOnFloor())
		{
			velocity += GetGravity() * (float)delta;
		}

		// Handle Jump.
		if (Input.IsActionJustPressed("jump") && IsOnFloor())
		{
			// check if jump is unlocked in game settings
			// Replace with your actual unlocks check logic
			// Example: if you have a singleton or autoload called "Unlocks", use:
			var unlocks = GetNodeOrNull<Node>("/root/Unlocks");
			if (unlocks != null && (bool)unlocks.Call("can", "PF:HighJump"))
			{
				velocity.Y = JumpVelocity;
			}
			else if (unlocks == null)
			{
				GD.PrintErr("Unlocks node not found. Jump will not be performed.");
			}
		}

		// Get the input direction and handle the movement/deceleration.
		// As good practice, you should replace UI actions with custom gameplay actions.
		Vector2 inputDir = Input.GetVector("move_left", "move_right", "move_up", "move_down");
		Vector3 direction = (Transform.Basis * new Vector3(inputDir.X, 0, inputDir.Y)).Normalized();

		if (direction != Vector3.Zero)
		{
			velocity.X = direction.X * Speed;
			velocity.Z = direction.Z * Speed;

			// Rotate velocity vector 45 degrees always to match isometric view
			float angle = Mathf.Pi / 4; // 45 degrees in radians
			float cosAngle = Mathf.Cos(angle);
			float sinAngle = Mathf.Sin(angle);
			float rotatedX = velocity.X * cosAngle - velocity.Z * sinAngle;
			float rotatedZ = velocity.X * sinAngle + velocity.Z * cosAngle;
			velocity.X = rotatedX;
			velocity.Z = rotatedZ;

			// Calculate the target rotation based on movement direction
			float targetAngle = Mathf.Atan2(rotatedX, rotatedZ);

			// Get the armature node and rotate it instead of the whole character
			var armature = GetNode<Node3D>("Armature"); // Adjust path as needed
			if (armature != null)
			{
				// Smoothly rotate towards the target angle
				float currentAngle = armature.Rotation.Y;
				float angleDifference = Mathf.AngleDifference(currentAngle, targetAngle);
				float rotationStep = TurnSpeed * (float)delta;

				// Clamp the rotation step to avoid overshooting
				if (Mathf.Abs(angleDifference) < rotationStep)
				{
					armature.Rotation = new Vector3(armature.Rotation.X, targetAngle, armature.Rotation.Z);
				}
				else
				{
					float newAngle = currentAngle + Mathf.Sign(angleDifference) * rotationStep;
					armature.Rotation = new Vector3(armature.Rotation.X, newAngle, armature.Rotation.Z);
				}
			}
		}
		else
		{
			velocity.X = Mathf.MoveToward(Velocity.X, 0, Speed);
			velocity.Z = Mathf.MoveToward(Velocity.Z, 0, Speed);
		}



		if (canMove)
		{
			Velocity = velocity;
		}

		MoveAndSlide();
		playFootstepSound(Velocity.Length());
		PlayWalkAnimation(Velocity.Length());
	}

	public void DisableInput()
	{
		canMove = false;
		canvasLayer.Visible = false;
	}

	public void EnableInput()
	{
		canMove = true;
		canvasLayer.Visible = true;
	}

	public void playHarvestAnimation()
	{
		if (animationPlayer == null)
			return;

		if (animationPlayer.IsPlaying())
		{
			animationPlayer.Stop();
		}
		animationPlayer.Play("harvest");
		animationPlayer.AnimationFinished += OnHarvestAnimationFinished;
	}

	private void OnHarvestAnimationFinished(StringName animName)
	{
		if (animName == "harvest" && animationPlayer != null)
		{
			animationPlayer.AnimationFinished -= OnHarvestAnimationFinished;
			animationPlayer.Play("idle");
		}
	}

	public void PlayWalkAnimation(float speed)
	{
		if (animationPlayer == null)
			return;

		if (IsOnFloor() && speed > 0.1f)
		{
			if (!animationPlayer.IsPlaying() || animationPlayer.CurrentAnimation != "walking")
			{
				animationPlayer.Play("walking");
			}
		}
		else
		{
			// Only play idle if walking animation is currently playing
			if (animationPlayer.IsPlaying() && animationPlayer.CurrentAnimation == "walking")
			{
				animationPlayer.Play("idle");
			}
		}
	}


	public void playFootstepSound(float speed)
	{
		var footstepPlayer = GetNode<AudioStreamPlayer3D>("FootstepSound");
		if (IsOnFloor() && speed > 0.1f)
		{
			if (!footstepPlayer.Playing)
			{
				footstepPlayer.PitchScale = 0.3f + (speed / Speed) * 0.4f; // Pitch between 0.8 and 1.2 based on speed
				footstepPlayer.Play();
			}
		}
		else
		{
			footstepPlayer.Stop();
		}
	}

	public void _on_area_3d_body_entered(Node3D body)
	{
		if (body.IsInGroup("interactable_signs"))
		{
			// Look for a Control child
			var signLabel = body.GetNode<Label>("Label");
			var popup = GetNode<Label>("/root/main/UserInterface/Panel/Panel/Popup");
			popup.Text = signLabel.Text;
			var signUI = GetNode<Panel>("/root/main/UserInterface/Panel");
			// Change visibility of signUI
			signUI.Visible = true;

		}
	}

	public void _on_area_3d_body_exited(Node3D body)
	{
		if (body.IsInGroup("interactable_signs"))
		{
			var signUI = GetNode<Panel>("CanvasLayer/UserInterface/Panel");
			signUI.Visible = false;
		}
	}

	public Inventory GetInventory()
	{
		string relativePath = "CanvasLayer/Inventory";
		return GetNode<Inventory>(relativePath);
	}

	public Bank GetBank()
	{
		string relativePath = "CanvasLayer/Bank";
		return GetNode<Bank>(relativePath);
	}

	public void SetInteractSpeed(float speed)
	{
		InteractingComponent interactComp = GetNodeOrNull<InteractingComponent>("InteractingComponent");
		interactComp.SetInteractSpeed(speed);
	}
}
