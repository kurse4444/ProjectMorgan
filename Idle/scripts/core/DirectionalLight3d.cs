using Godot;
using System;
using System.IO;

public partial class DirectionalLight3d : DirectionalLight3D
{
    [Export] public float TotalDayTimeSeconds = 128f;
    [Export] public Vector3 RotationAxis = Vector3.Right;
    [Export] public float FadeDuration = 5f; // Fade duration in seconds
    [Export] public float MinVolumeDb = -80f; // Minimum volume (essentially muted)
    public Light3D MoonLight;

    private float RotationSpeed;
    AudioStreamPlayer dayAudioPlayer;
    AudioStreamPlayer nightAudioPlayer;
    private Tween dayTween;
    private Tween nightTween;

    // Track current music state to prevent continuous calls
    private enum MusicState { Day, Night, Stopped }
    private MusicState currentMusicState = MusicState.Stopped;

    public override void _Ready()
    {
        RotationSpeed = 180f / TotalDayTimeSeconds;
        RotationDegrees = new Vector3(-90, 0, 0);
        dayAudioPlayer = GetNode<AudioStreamPlayer>("DaySong");
        nightAudioPlayer = GetNode<AudioStreamPlayer>("NightSong");

        GD.Print($"[READY] Initial setup - MinVolumeDb: {MinVolumeDb}, FadeDuration: {FadeDuration}");

        // Start with both tracks at min volume
        dayAudioPlayer.VolumeDb = MinVolumeDb;
        nightAudioPlayer.VolumeDb = MinVolumeDb;

        // Fade in day song at start
        dayAudioPlayer.Play();
        dayTween = CreateTween();
        nightTween = CreateTween();
        dayTween.TweenProperty(dayAudioPlayer, "volume_db", 0f, FadeDuration);

        currentMusicState = MusicState.Day;
        GD.Print($"[READY] Started with day music");

        MoonLight = GetNode<Light3D>("Moon");
    }

    public override void _Process(double delta)
    {
        // Rotate sun
        RotateObjectLocal(RotationAxis.Normalized(), Mathf.DegToRad(RotationSpeed * (float)delta));
        HandleMusic(RotationDegrees.X % 360);
    }

    public void HandleMusic(float angle)
    {
        float[] dayAngles = new float[] { -165f, -15f };
        float[] nightAngles = new float[] { 15f, 150f };

        NormalizeAngle(ref angle);
        NormalizeAngle(ref dayAngles[0]);
        NormalizeAngle(ref dayAngles[1]);
        NormalizeAngle(ref nightAngles[0]);
        NormalizeAngle(ref nightAngles[1]);

        if (angle > dayAngles[0] && angle < dayAngles[1])
        {
            // Only start day song if we're not already in day state
            if (currentMusicState != MusicState.Day)
            {
                GD.Print($"[HANDLE_MUSIC] Angle {angle} in day range, starting day song");
                StartDaySong();
            }
        }
        else if (angle > nightAngles[0] && angle < nightAngles[1])
        {
            // Only start night song if we're not already in night state
            if (currentMusicState != MusicState.Night)
            {
                GD.Print($"[HANDLE_MUSIC] Angle {angle} in night range, starting night song");
                StartNightSong();
            }
        }
        else
        {
            // Only stop music if we're not already stopped
            if (currentMusicState != MusicState.Stopped)
            {
                GD.Print($"[HANDLE_MUSIC] Angle {angle} outside ranges, stopping all music");
                StopAllMusic();
            }
        }
    }

    private void NormalizeAngle(ref float angle)
    {
        while (angle < 0) angle += 360;
        while (angle >= 360) angle -= 360;
    }

    public async void StartDaySong()
    {
        GD.Print($"[START_DAY] ===== STARTING DAY SONG =====");

        currentMusicState = MusicState.Day;

        dayAudioPlayer.Stop();
        await ToSignal(GetTree(), SceneTree.SignalName.ProcessFrame);

        dayAudioPlayer.VolumeDb = MinVolumeDb;
        dayAudioPlayer.Play();
        await ToSignal(GetTree(), SceneTree.SignalName.ProcessFrame);

        // Kill existing tweens
        if (dayTween != null && dayTween.IsValid())
        {
            dayTween.Kill();
        }
        if (nightTween != null && nightTween.IsValid())
        {
            nightTween.Kill();
        }

        await ToSignal(GetTree(), SceneTree.SignalName.ProcessFrame);

        dayTween = CreateTween();
        dayTween.TweenProperty(dayAudioPlayer, "volume_db", 0f, FadeDuration);

        // Fade out night song if playing
        if (nightAudioPlayer.Playing)
        {
            nightTween = CreateTween();
            nightTween.TweenProperty(nightAudioPlayer, "volume_db", MinVolumeDb, FadeDuration);
        }

        GD.Print($"[START_DAY] Day song started and fading in from {MinVolumeDb} to 0");
    }

    public async void StartNightSong()
    {
        GD.Print($"[START_NIGHT] ===== STARTING NIGHT SONG =====");

        currentMusicState = MusicState.Night;

        nightAudioPlayer.Stop();
        await ToSignal(GetTree(), SceneTree.SignalName.ProcessFrame);

        nightAudioPlayer.VolumeDb = MinVolumeDb;
        nightAudioPlayer.Play();
        await ToSignal(GetTree(), SceneTree.SignalName.ProcessFrame);

        // Kill existing tweens
        if (dayTween != null && dayTween.IsValid())
        {
            dayTween.Kill();
        }
        if (nightTween != null && nightTween.IsValid())
        {
            nightTween.Kill();
        }

        await ToSignal(GetTree(), SceneTree.SignalName.ProcessFrame);

        nightTween = CreateTween();
        nightTween.TweenProperty(nightAudioPlayer, "volume_db", 0f, FadeDuration);

        // Fade out day song if playing
        if (dayAudioPlayer.Playing)
        {
            dayTween = CreateTween();
            dayTween.TweenProperty(dayAudioPlayer, "volume_db", MinVolumeDb, FadeDuration);
        }

        GD.Print($"[START_NIGHT] Night song started and fading in from {MinVolumeDb} to 0");
    }

    public void StopAllMusic()
    {
        GD.Print($"[STOP_ALL] ===== STOPPING ALL MUSIC =====");

        currentMusicState = MusicState.Stopped;

        // Kill existing tweens
        if (dayTween != null && dayTween.IsValid())
        {
            dayTween.Kill();
        }
        if (nightTween != null && nightTween.IsValid())
        {
            nightTween.Kill();
        }

        dayTween = CreateTween();
        nightTween = CreateTween();

        dayTween.TweenProperty(dayAudioPlayer, "volume_db", MinVolumeDb, FadeDuration);
        nightTween.TweenProperty(nightAudioPlayer, "volume_db", MinVolumeDb, FadeDuration);

        GD.Print("[STOP_ALL] Started fade out tweens - music will stop calling this method now");
    }

    // Add this method to stop all music when muting
    public void StopMusic()
    {
        GD.Print("[STOP_MUSIC] Stopping all music");
        
        // Kill tweens
        if (dayTween != null && dayTween.IsValid())
            dayTween.Kill();
        if (nightTween != null && nightTween.IsValid())
            nightTween.Kill();
        
        // Stop players
        dayAudioPlayer.Stop();
        nightAudioPlayer.Stop();
        
        // Reset state so music will restart fresh
        currentMusicState = MusicState.Stopped;
    }

    // Add this method to restart music when unmuting
    public void RestartMusic()
    {
        GD.Print("[RESTART_MUSIC] Restarting music");
        
        // Force a fresh evaluation
        currentMusicState = MusicState.Stopped;
        float currentAngle = RotationDegrees.X % 360;
        HandleMusic(currentAngle);
    }
}