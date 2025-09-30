using Godot;

public partial class ItemSlot : Panel
{
	[Signal]
	public delegate void SlotClickedEventHandler(ItemSlot slot);

	private TextureRect icon;
	private bool isSelected = false;
	private Label quantityLabel;
	private Item item;

	public override void _Ready()
	{
		item = null;
		icon = GetNode<TextureRect>("Icon");
		quantityLabel = GetNode<Label>("QuantityLabel");
		Deselect();
	}

	public override void _GuiInput(InputEvent @event)
	{
		if (@event is InputEventMouseButton mouseEvent && mouseEvent.Pressed && mouseEvent.ButtonIndex == MouseButton.Left)
		{
			EmitSignal(SignalName.SlotClicked, this);
		}
	}

	public override void _Process(double delta)
	{
	}

	private StyleBoxFlat CreateSelectedStyleBox()
	{
		var styleBox = new StyleBoxFlat
		{
			BorderColor = new Color(1, 1, 1), // yellow border
			BgColor = new Color(1, 1, 0.6f, 0.5f), // light yellow background
			BorderBlend = true
		};
		styleBox.SetBorderWidth(Side.Left, 3);
		styleBox.SetBorderWidth(Side.Top, 3);
		styleBox.SetBorderWidth(Side.Right, 3);
		styleBox.SetBorderWidth(Side.Bottom, 3);
		return styleBox;
	}

	private StyleBoxFlat CreateDeselectedStyleBox()
	{
		var styleBox = new StyleBoxFlat
		{
			BorderColor = new Color(.2f, .2f, .2f), // black border
			BgColor = new Color(1, 1, 1, 0.3f), // transparent background
			BorderBlend = true
		};
		styleBox.SetBorderWidth(Side.Left, 3);
		styleBox.SetBorderWidth(Side.Top, 3);
		styleBox.SetBorderWidth(Side.Right, 3);
		styleBox.SetBorderWidth(Side.Bottom, 3);
		return styleBox;
	}


	public bool Select()
	{
		if (item == null) return false; // don't select empty slots
		isSelected = true;
		AddThemeStyleboxOverride("panel", CreateSelectedStyleBox());
		Modulate = new Color(1, 1, 1, 1f); // ensure fully visible
		return true;
	}

	public void Deselect()
	{
		// Remove the custom stylebox to revert to default appearance
		AddThemeStyleboxOverride("panel", CreateDeselectedStyleBox());
		Modulate = new Color(1, 1, 1, 1f);
		GD.Print("Deselected ", Name);
	}

	public void SetItem(Item item, int amount)
	{
		// Implement logic to set item and quantity
		GD.Print($"Set item to {item.Name} with quantity {amount}");
		this.item = item;
		this.item.Quantity = amount;
		UpdateSlot();
	}

	public void UpdateSlot()
	{
		if (this.item.Quantity <= 0)
		{
			this.item = null;
			icon.Texture = null;
			quantityLabel.Text = "";
			quantityLabel.Visible = false;
			Deselect();
			return;
		}
		icon.Texture = item?.Icon;
		quantityLabel.Text = item.Quantity.ToString();
		quantityLabel.Visible = item != null && item.Quantity > 1;
	}

	public Item GetItem()
	{
		GD.Print("Getting item from slot: " + Name + " Item: " + item?.Name);
		return item;
	}
}
