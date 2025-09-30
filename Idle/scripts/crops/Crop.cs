using Godot;
using System;

[GlobalClass]
public partial class Crop : Resource
{
    [Export] public string CropName { get; set; } = "";
    [Export] public Item HarvestItem { get; set; }
    [Export] public Seeds Seed { get; set; }
    [Export] public int CurrentStage { get; set; } = 0;
    [Export] public bool IsMature { get; set; } = false;
    [Export] public bool IsPlanted { get; set; } = false;

    // 3D models for each growth stage
    [Export] public PackedScene[] StageModels { get; set; } = new PackedScene[0];
    [Export] public float TimePerStage { get; set; } = 60f;
    [Export] public float GrowthTimeVariance { get; set; } = 0.1f; // 10% variance

    public int Stages => StageModels?.Length ?? 0;

    public PackedScene GetCurrentModel()
    {
        if (StageModels == null || CurrentStage >= StageModels.Length)
            return null;
        return StageModels[CurrentStage];
    }
    public float GetRandomGrowthTime()
    {
        float baseTime = TimePerStage;
        float variance = baseTime * GrowthTimeVariance;
        return (float)GD.RandRange(baseTime - variance, baseTime + variance);
    }
}