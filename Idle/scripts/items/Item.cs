using Godot;
using System;

[GlobalClass]
public partial class Item : Resource
{
    [Export] public string Id { get; set; } = "";
    [Export] public string Name { get; set; } = "";
    [Export] public string Description { get; set; } = "";
    [Export] public Texture2D Icon { get; set; }
    [Export] public int StackSize { get; set; } = 1;
    [Export] public int Quantity { get; set; } = 1;
    [Export] public int Value { get; set; } = 0;
}
