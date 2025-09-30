using Godot;

[GlobalClass]
public partial class Seeds : Item
{
    [Export] public Crop CropToGrow { get; set; }
}