using Godot;
using System;

public partial class Main : Node3D
{

	public void HideLevel()
	{
		this.Visible = false;
		// mute all sounds
		var audio_bus = AudioServer.GetBusIndex("Idle_Music");
		AudioServer.SetBusMute(audio_bus, true);

		// disable player input
		var player = GetNode<CharacterBody3d>("Character/CharacterBody3D");
		player.DisableInput();
	}
	public void ShowLevel()
	{
		this.Visible = true;
		// unmute all sounds
		var audio_bus = AudioServer.GetBusIndex("Idle_Music");
		AudioServer.SetBusMute(audio_bus, false);

		// enable player input
		var player = GetNode<CharacterBody3d>("Character/CharacterBody3D");
		player.EnableInput();
	}
}
