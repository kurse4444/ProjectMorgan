using Godot;
using System;
using System.ComponentModel;

public partial class Inventory : Panel
{
	public Item[] AllItems { get; set; }
	public Item[] AllTools { get; set; }
	private ItemSlot selectedSlot;

	private GridContainer ItemSlots;
	private GridContainer ToolSlots;
	
	private CharacterBody3d player;
	// Called when the node enters the scene tree for the first time.
	public override void _Ready()
	{
		ItemSlots = GetNode("Items/MarginContainer/GridContainer") as GridContainer;
		ToolSlots = GetNode("Tools/MarginContainer/GridContainer") as GridContainer;

		player = GetParent<CanvasLayer>().GetParent<CharacterBody3d>();

		int itemSlots = ItemSlots.GetChildCount();
		AllItems = new Item[itemSlots];

		int toolSlots = ToolSlots.GetChildCount();
		AllTools = new Item[toolSlots];



		// For testing, add some items to the inventory
		// string carrotPath = "res://items/carrot_seeds.tres";
		// Item carrot = GD.Load<Item>(carrotPath);
		// AddItem(carrot, 5);

		// string bombPath = "res://items/bomb.tres";
		// Item bomb = GD.Load<Item>(bombPath);
		// AddItem(bomb, 1);

	}

	// Called every frame. 'delta' is the elapsed time since the previous frame.
	public override void _Process(double delta)
	{
	}

	public void _on_item_slot_slot_clicked(ItemSlot slot)
	{
		GD.Print("Slot clicked");
		GD.Print(slot.Name);
		if (slot == selectedSlot)
		{
			// deselect all other slots
			deselectAllSlots(ItemSlots);
			deselectAllSlots(ToolSlots);
			return;
		}
		else
		{
			// deselect all other slots
			deselectAllSlots(ItemSlots);
			deselectAllSlots(ToolSlots);

			bool results = slot.Select();
			if (!results) return; // don't select empty slots
			selectedSlot = slot;
		}
	}

	public void deselectAllSlots(GridContainer grid)
	{
		var slots = grid.GetChildren();
		foreach (var child in slots)
		{
			(child as ItemSlot)?.Deselect();
			GD.Print(child.Name);
		}
		selectedSlot = null;
	}

	public Item GetSelectedItem()
	{
		return selectedSlot?.GetItem();
	}

	public ItemSlot GetSelectedSlot()
	{
		return selectedSlot;
	}

	public bool AddItem(Item item, int quantity = 1)
	{
		if (item is Tool)
		{
			return AddTool(item as Tool, quantity);
		}
		else
		{
			return AddRegularItem(item, quantity);
		}
	}
	private bool AddRegularItem(Item item, int quantity = 1)
	{
		if (item == null) return false;

		GD.Print($"Adding {quantity} {item.Name}(s) to items");
		GD.Print($"Item ID: {item.Id}");
		GD.Print($"Item Description: {item.Description}");

		// Add to actual inventory slots
		var slots = ItemSlots.GetChildren();
		foreach (var child in slots)
		{
			var slot = child as ItemSlot;
			if (slot != null)
			{
				// If the slot is empty, add the item here
				if (slot.GetItem() == null)
				{
					slot.SetItem(item, quantity);
					GD.Print($"Placed in slot: {slot.Name}");
					return true;
				}
				// If the slot has the same item and can stack, add to this slot
				else if (slot.GetItem() != null && slot.GetItem().Id == item.Id && slot.GetItem().Quantity + quantity <= item.StackSize)
				{
					slot.SetItem(item, slot.GetItem().Quantity + quantity);
					GD.Print($"Stacked in slot: {slot.Name}");
					return true;
				}
			}
		}
		GD.Print("No available slot found for the item");
		return false;
	}

	private bool AddTool(Tool item, int quantity = 1)
	{
		if (item == null) return false;

		GD.Print($"Adding {quantity} {item.Name}(s) to tools");
		GD.Print($"Item ID: {item.Id}");
		GD.Print($"Item Description: {item.Description}");

		// Add to actual inventory slots
		var slots = ToolSlots.GetChildren();
		foreach (var child in slots)
		{
			var slot = child as ItemSlot;
			if (slot != null)
			{
				// If the slot is empty, add the item here
				if (slot.GetItem() == null)
				{
					slot.SetItem(item, quantity);
					GD.Print($"Placed in slot: {slot.Name}");
					applyToolEffects(item);
					return true;
				}
				else
				{
					GD.Print($"Tool slot {slot.Name} already occupied");
				}
			}
		}
		GD.Print("No available slot found for the item");
		return false;
	}

	private void applyToolEffects(Tool item)
	{
		// get unlocks 
		var unlocks = GetNodeOrNull<Node>("/root/Unlocks");
		if (item == null) return;
		if (item.Id == "farm_tools")
		{
			GD.Print("Applying farming tool effects", item.EffectValue);
			player.SetInteractSpeed(item.EffectValue);
		}
		else if (item.Id == "time_bubble")
		{
			if (unlocks != null && (bool)unlocks.Call("can", "FoundBubble"))
			{
				GD.Print("Applying time bubble effects", item.EffectValue);
				unlocks.Call("mark_milestone", "FoundBubble");
			}
			else if (unlocks == null)
			{
				GD.PrintErr("Unlocks node not found. Time bubble effects will not be applied.");
			}
		}
		else if (item.Id == "bomb")
		{
			if (unlocks != null && (bool)unlocks.Call("can", "FoundBomb"))
			{
				GD.Print("Applying bomb effects", item.EffectValue);
				unlocks.Call("mark_milestone", "FoundBomb");
			}
			else if (unlocks == null)
			{
				GD.PrintErr("Unlocks node not found. Bomb effects will not be applied.");
			}
		}
		else
		{
			GD.Print("No special effects for this tool");
		}
	}

	public void UseItem()
	{
		if (selectedSlot == null || selectedSlot.GetItem() == null) return;

		// Remove one quantity of the item
		GD.Print("Using item: " + selectedSlot.GetItem().Quantity + " of " + selectedSlot.GetItem().Name);
		selectedSlot.SetItem(selectedSlot.GetItem(), selectedSlot.GetItem().Quantity - 1);
	}
}