using Godot;

public partial class Outro : Control
{
    private VideoStreamPlayer _videoPlayer;
    private TextureRect _videoDisplay;
    private ColorRect _fadeRect;
    private Label _thankYouLabel;
    private string _videoPath = "res://Cutscenes/end ogg.ogv";
    private bool _fading = false;
    
    public void Setup(string videoPath)
    {
        _videoPath = videoPath;
    }
    
    public override void _Ready()
    {
        var windowSize = DisplayServer.WindowGetSize();
        Size = windowSize;
        Position = Vector2.Zero;
        
        _videoPlayer = new VideoStreamPlayer();
        AddChild(_videoPlayer);
        
        var videoStream = GD.Load<VideoStream>(_videoPath);
        if (videoStream == null)
        {
            GD.PrintErr($"Failed to load video stream: {_videoPath}");
            OnVideoFinished();
            return;
        }
        
        _videoPlayer.Stream = videoStream;
        _videoPlayer.Loop = false;
        _videoPlayer.VolumeDb = 0;
        _videoPlayer.Paused = false;
        
        _videoDisplay = new TextureRect();
        AddChild(_videoDisplay);
        _videoDisplay.Size = windowSize;
        _videoDisplay.Position = Vector2.Zero;
        _videoDisplay.ExpandMode = TextureRect.ExpandModeEnum.IgnoreSize;
        _videoDisplay.StretchMode = TextureRect.StretchModeEnum.KeepAspectCovered;
        
        _fadeRect = new ColorRect();
        _fadeRect.Color = new Color(0, 0, 0, 0);
        _fadeRect.Size = windowSize;
        _fadeRect.Position = Vector2.Zero;
        AddChild(_fadeRect);
        
        _thankYouLabel = new Label();
        _thankYouLabel.Text = "Thank You For Playing!";
        _thankYouLabel.Visible = false;
        _thankYouLabel.Size = windowSize;
        _thankYouLabel.Position = Vector2.Zero;
        _thankYouLabel.HorizontalAlignment = HorizontalAlignment.Center;
        _thankYouLabel.VerticalAlignment = VerticalAlignment.Center;
        _thankYouLabel.AddThemeColorOverride("font_color", Colors.White);
        _thankYouLabel.AddThemeFontSizeOverride("font_size", 24);
        AddChild(_thankYouLabel);
        
        _videoPlayer.Finished += OnVideoFinished;
        _videoPlayer.Play();
    }
    
    public override void _Process(double delta)
    {
        if (_videoPlayer != null && _videoPlayer.IsPlaying())
        {
            var texture = _videoPlayer.GetVideoTexture();
            if (texture != null)
            {
                _videoDisplay.Texture = texture;
            }
        }
        
        if (!_fading && (Input.IsActionJustPressed("ui_cancel") || Input.IsActionJustPressed("ui_accept")))
        {
            OnVideoFinished();
        }
    }
    
    private void OnVideoFinished()
    {
        if (_fading) return;
        _fading = true;
        
        var tween = CreateTween();
        tween.TweenProperty(_fadeRect, "color:a", 1.0f, 1.5f)
            .SetTrans(Tween.TransitionType.Sine)
            .SetEase(Tween.EaseType.InOut);
        tween.TweenCallback(Callable.From(ShowThankYou));
    }
    
    private void ShowThankYou()
    {
        _thankYouLabel.Visible = true;
    }
}