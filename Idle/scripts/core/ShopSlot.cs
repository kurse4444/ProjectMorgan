using Godot;
using System;

public partial class ShopSlot : Panel
{
	[Signal]
	public delegate void SlotClickedEventHandler(ShopSlot slot);
	[Signal]
	public delegate void SlotHoverEventHandler(ShopSlot slot);
	private Label priceTag;
	private Label nameTag;
	private TextureRect icon;
	[Export]
	private Item item;
	// Called when the node enters the scene tree for the first time.
	public override void _Ready()
	{
		priceTag = GetNode<Label>("Price");
		nameTag = GetNode<Label>("Name");
		icon = GetNode<TextureRect>("Icon");
		priceTag.Text = item.Value.ToString();
		nameTag.Text = item.Name;
		icon.Texture = item.Icon;

	}

	// Called every frame. 'delta' is the elapsed time since the previous frame.
	public override void _Process(double delta)
	{
	}

	public override void _GuiInput(InputEvent @event)
	{
		if (@event is InputEventMouseButton mouseEvent && mouseEvent.Pressed && mouseEvent.ButtonIndex == MouseButton.Left)
		{
			EmitSignal(SignalName.SlotClicked, this);
		}
		else if (@event is InputEventMouseMotion)
		{
			EmitSignal(SignalName.SlotHover, this);
		}
	}

	public int getPrice()
	{
		return int.Parse(priceTag.Text);
	}

	public string getName()
	{
		return nameTag.Text;
	}
	public Item GetItem()
	{
		return item;
	}

	public void RemoveItem()
	{
		item = null;
		priceTag.Text = "";
		nameTag.Text = "";
		icon.Texture = null;
	}
}
