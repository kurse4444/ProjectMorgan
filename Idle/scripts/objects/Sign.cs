using Godot;
using System;

public partial class Sign : StaticBody3D
{
	private Panel panel;
	[Export] public string Text { get; set; } = "";

	private CharacterBody3d player;

	public override void _Ready()
	{
	}
	
	public void interact(CharacterBody3d player)
	{
		ShowPanel(player);
	}

	private void ShowPanel(CharacterBody3d player)
	{
		GD.Print("Showing sign panel with text: " + Text);
		player.GetNode<Panel>("CanvasLayer/Sign").Visible = true;
		player.GetNode<Label>("CanvasLayer/Sign/Panel/Popup").Text = Text;
		this.player = player;
	}
	
	public override void _Input(InputEvent @event)
	{

		// Close the panel on any key press or mouse button press
		if (@event is InputEventKey keyEvent && keyEvent.Pressed ||
			@event is InputEventMouseButton mouseEvent && mouseEvent.Pressed ||
			@event is InputEventJoypadButton joypadEvent && joypadEvent.Pressed)
		{
			HidePanel();
		}
	}
	
	private void HidePanel()
	{
		if (player == null) return;
		GD.Print("Hiding sign panel");
		player.GetNode<Panel>("CanvasLayer/Sign").Visible = false;
	}
}
