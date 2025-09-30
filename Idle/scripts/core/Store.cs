using Godot;
using System;

public partial class Store : Panel
{
	// Called when the node enters the scene tree for the first time.
	private Bank bank;
	private Inventory inventory;
	// private Panel tooltip;
	public override void _Ready()
	{
		bank = GetNode<Bank>("../Bank");
		inventory = GetNode<Inventory>("../Inventory");
	}

	// Called every frame. 'delta' is the elapsed time since the previous frame.
	public override void _Process(double delta)
	{
	}

	public void _on_shop_slot_slot_clicked(ShopSlot slot)
	{
		GD.Print("Shop Slot clicked");
		GD.Print(slot.getName());
		GD.Print(slot.getPrice());
		purchaseItem(slot);
		
	}

	public void _on_shop_slot_slot_hover(ShopSlot slot)
	{
		// var itemDescription = GetNode<Label>("ItemDescription");
		// itemDescription.Text = slot.GetItem().Description;
		// TODO: Position tooltip near mouse
	}

	public void purchaseItem(ShopSlot slot)
	{
		Item item = slot.GetItem();
		// get selected item from inventory
		if (bank.DeductFunds(slot.getPrice()))
		{
			if (inventory.AddItem(item, 1))
			{
				GD.Print("Successfully added item to inventory: " + slot.getName());
				// remove from shop if tool
				if (item is Tool)
				{
					GD.Print("Removing tool from shop: " + slot.getName());
					slot.RemoveItem();
				}
			}
			GD.Print("Purchased item: " + slot.getName());
			// play sound
			GetNode<AudioStreamPlayer3D>("PurchaseSound").Play();
		}
		else
		{
			GD.Print("Not enough funds to purchase item: " + slot.getName());
			// play sound
			// GetNode<AudioStreamPlayer3D>("ErrorSound").Play();
			return;
		}
		GD.Print("Purchasing item: " + slot.getName());
	}
}
