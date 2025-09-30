using Godot;
using System;

public partial class Test : Node
{
    CanvasLayer MainMenu;
    Node3D IdleLevel;
    Node2D PlatformerLevel;
    public override void _Ready()
    {
        MainMenu = GetNode<CanvasLayer>("MainMenu");
        IdleLevel = GetNode<Node3D>("IdleLevel");
        PlatformerLevel = GetNode<Node2D>("PlatformerLevel");

        PlatformerLevel.Call("HideLevel");
        IdleLevel.Call("HideLevel");
    }

    public override void _Process(double delta)
    {
        if (Input.IsActionJustPressed("show_menu"))
        {
            // Switch scene to main menu
            MainMenu.Call("show_menu");
        }
    }

    public void StartIdleGame()
    {
        MainMenu.Call("hide_menu");
        PlatformerLevel.Call("HideLevel");

        IdleLevel.Call("ShowLevel");
    }

    public void StartPlatformerGame()
    {
        MainMenu.Call("hide_menu");
        IdleLevel.Call("HideLevel");

        PlatformerLevel.Call("ShowLevel");
    }
    
    public void ResetPlatformerLevel()
    {
        // Remove current PlatformerLevel
        PlatformerLevel.QueueFree();

        // Instance a new PlatformerLevel from the scene file
        var newPlatformerLevel = (Node2D)GD.Load<PackedScene>("res://Platformer/Scenes/platformer_level.tscn").Instantiate();

        // Add the new PlatformerLevel to the scene tree
        AddChild(newPlatformerLevel);

        // Update the reference to the new PlatformerLevel
        PlatformerLevel = newPlatformerLevel;
    }
}
