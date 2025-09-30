using Godot;
using System;

public partial class Bank : Panel
{
	[Export]
	public int Money;
	// Called when the node enters the scene tree for the first time.
	public override void _Ready()
	{
		updateLabel();
	}

	// Called every frame. 'delta' is the elapsed time since the previous frame.
	public override void _Process(double delta)
	{
	}

	public void AddFunds(int amount)
	{
		GD.Print("Added " + amount + " funds to bank.");
		// Update bank Money Label
		Money += amount;
		updateLabel();
	}

	public bool DeductFunds(int amount)
	{
		if (Money < amount)
		{
			GD.Print("Not enough funds in bank.");
			return false;
		}
		Money -= amount;
		updateLabel();
		GD.Print("Deducted " + amount + " funds from bank.");
		return true;
	}

	public string formatMoney(int amount)
	{
		return amount.ToString("D7");
	}

	public void updateLabel()
	{
		var moneyLabel = GetNode<Label>("MoneyLabel");
		moneyLabel.Text = formatMoney(Money);
	}
}
