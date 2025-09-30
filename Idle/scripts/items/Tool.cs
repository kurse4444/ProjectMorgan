using Godot;
using System;

[GlobalClass]
public partial class Tool : Item
{
    [Export] public float EffectValue { get; set; } = 0.2f;
}