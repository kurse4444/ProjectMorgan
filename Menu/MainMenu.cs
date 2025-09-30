using Godot;
using System;

public partial class MainMenu : CanvasLayer
{
	public void hide_menu()
	{
		this.Visible = false;
	}
	public void show_menu()
	{
		this.Visible = true;
	}

	public void _on_button_idle_pressed()
	{
		GetParent().Call("StartIdleGame");
	}

	public void _on_button_pf_pressed()
	{
		GetParent().Call("StartPlatformerGame");
	}
}
