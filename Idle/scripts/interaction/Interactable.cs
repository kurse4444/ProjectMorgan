using Godot;
using System;

public partial class Interactable : Area3D
{
	[Export] public string interact_name = "";
	[Export] public bool is_interactable = true;
	
	private Callable interact;
	
	public override void _Ready()
	{
		GD.Print("interactable ready");
		interact = new Callable(this, nameof(InteractMethod));
	}
	
	private void InteractMethod()
	{
		// Your interaction logic here
	}
}
