using Godot;
using System;
using System.ComponentModel;

public partial class BridgeBuilding : Node3D
{
    public MeshInstance3D bridge;
    public CollisionShape3D collision;
    public MeshInstance3D logs;

    public override void _Ready()
    {
        bridge = GetNode<MeshInstance3D>("BridgeWood");
        if (bridge == null)
            GD.PrintErr("BridgeWood node not found. Check the node path.");
        collision = GetNode<CollisionShape3D>("River/StaticBody3D/CollisionShape3D");
        logs = GetNode<MeshInstance3D>("LogStackLarge");
    }
    public void interact(CharacterBody3d player)
    {
        if (player.GetBank().DeductFunds(50000))
        {
            buildBridge();
        }
        else
        {
            GD.Print("Not enough funds to build bridge.");
        }
    }

    public void buildBridge()
    {
        bridge.Visible = true;
        logs.Visible = false;

        // Remove barrier
        collision.Disabled = true;

        // Play sound
        // GetNode<AudioStreamPlayer3D>("AudioStreamPlayer3D").Play();
        // remove balance from player

    }
}
