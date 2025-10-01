using Godot;
using System;
using System.Xml.XPath;

// contains a crop
public partial class Planter : Node3D
{
	private Crop current_crop;
	private Seeds current_seeds;
	private Node3D currentCropModel;
	private Timer growthTimer;
	private Timer pestTimer;
	private Node3D pestModel;
	private int timeDilation = 1;
	[Export]
	private float pestPower = 4; // multiplier for how much damage pests do
	[Export]
	private float pestAgressiveness = 0.08f; // chance of pest appearing each interval

	public override void _Ready()
	{
		current_crop = null;
		current_seeds = null;
		// Select the Timer node and connect its timeout signal
		growthTimer = GetNode<Timer>("GrowthTimer");
		pestTimer = GetNode<Timer>("PestTimer");
		pestModel = GetNode<Node3D>("Pest");
		pestModel.Visible = false;
	}

	public override void _Process(double delta)
	{
	}

	// listen for player interaction to run plant function on specific crop
	public bool interact(CharacterBody3D player)
	{
		GD.Print("Interacted with planter");
		if (pestModel.Visible)
		{
			KickPest();
			GD.Print("Removed pests from crop");
			return false;
		}
		if (isOccupied())
		{
			GD.Print("Planter is occupied, harvesting crop");
			Bank bank = player.GetNode<Bank>("CanvasLayer/Bank");
			GD.Print("Current crop null: " + current_crop != null + ", HarvestItem: " + current_crop.HarvestItem);
			bool result = Harvest(bank);
			if (result && current_seeds != null)
			{
				// add seeds to inventory
				Inventory inventory = player.GetNode<Inventory>("CanvasLayer/Inventory");
				inventory.AddItem(current_seeds, 1);
				GD.Print("Added harvested seeds to inventory");
			}
			return result;
		}
		else
		{
			GD.Print("Planter is empty, planting crop");
			Inventory inventory = player.GetNode<Inventory>("CanvasLayer/Inventory");
			if (Plant(inventory.GetSelectedItem()))
			{
				inventory.UseItem();
				return true;
			}
			return false;
		}
	}

	public bool Harvest(Bank bank)
	{
		if (current_crop != null && current_crop.CurrentStage == current_crop.Stages - 1)
		{
			
			// Store the harvested crop item
			int value = current_crop.HarvestItem.Value;
			bank.AddFunds(value);
			// Clear the current crop
			current_crop = null;
			UpdateCropVisuals();
			// play sound
			GetNode<AudioStreamPlayer3D>("HarvestSound").Play();

			pestTimer.Stop();
			return true;
		}
		else
		{
			GD.Print("Crop is not ready for harvest");
		}
		return false;
	}

	public bool Plant(Item item)
	{
		if (item is Seeds seedItem)
		{
			GD.Print("Planting crop from seeds: " + seedItem.Name);
			current_crop = seedItem.CropToGrow.Duplicate() as Crop;
			current_seeds = seedItem.Duplicate() as Seeds;
			RestartGrowthTimer();
			RestartPestTimer();
			UpdateCropVisuals();
			// play sound
			GetNode<AudioStreamPlayer3D>("PlantSound").Play();
			return true;
		}
		GD.Print("Item is not seeds, cannot plant");
		return false;
	}

	private void UpdateCropVisuals()
	{
		// Remove the previous crop model if it exists
		if (currentCropModel != null && currentCropModel.IsInsideTree())
		{
			currentCropModel.QueueFree();
			currentCropModel = null;
		}
		// Get the PackedScene for the current stage and instantiate it
		if (current_crop != null)
		{
			var stageModel = current_crop.GetCurrentModel();
			if (stageModel != null)
			{
				currentCropModel = stageModel.Instantiate<Node3D>();
				AddChild(currentCropModel);
				GD.Print("Planted crop model: " + currentCropModel.Name);
			}
		}
	}

	public bool isOccupied()
	{
		return current_crop != null;
	}

	public void _on_growth_timer_timeout()
	{
		if (current_crop == null) return;
		GD.Print("Crop grew to stage: " + current_crop.CurrentStage);
		// Update the crop model to the new stage
		addGrowth();
		
		if (current_crop.CurrentStage == current_crop.Stages - 1)
		{
			current_crop.IsMature = true;
			GD.Print("Crop is fully grown and ready to harvest");
			growthTimer.Stop();
		}
	}

	public void _on_pest_timer_timeout()
	{
		if (current_crop == null) return;
		if (pestModel.Visible)
		{
			// remove a growth stage if pests are present
			removeGrowth();
			GD.Print("Pests have damaged the crop! New stage: " + current_crop.CurrentStage);
		}
		if (GD.Randf() < pestAgressiveness && !pestModel.Visible) // chance to add pest if none present
		{
			AddPest();
			GD.Print("Pests have infested the crop!");
		}
		
		RestartPestTimer();
	}

	public void AddPest()
	{
		pestModel.Visible = true;
		// add random roatation
		pestModel.Rotation = new Vector3(0, GD.Randf() * Mathf.Pi * 2, 0);
		// play sound
		GetNode<AudioStreamPlayer3D>("PestSound").Play();
	}
	public void KickPest()
	{
		pestModel.Visible = false;
		// play sound
		GetNode<AudioStreamPlayer3D>("KickPest").Play();
		GetNode<AudioStreamPlayer3D>("PestSound").Stop();
		RestartPestTimer();
	}

	public void RestartGrowthTimer()
	{
		growthTimer.WaitTime = current_crop.GetRandomGrowthTime() * timeDilation;
		growthTimer.Start();
	}
	public void RestartPestTimer()
	{
		pestTimer.WaitTime = current_crop.TimePerStage / pestPower;
		pestTimer.Start();
	}

	public void addGrowth()
	{
		current_crop.CurrentStage++;
		UpdateCropVisuals();
		RestartGrowthTimer();
	}
	public void removeGrowth()
	{
		current_crop.CurrentStage = Math.Max(0, current_crop.CurrentStage - 1);
		UpdateCropVisuals();
		RestartGrowthTimer();
	}
}
