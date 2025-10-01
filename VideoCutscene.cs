using Godot;

public partial class VideoCutscene : Control
{
	private VideoStreamPlayer _videoPlayer;
	private TextureRect _videoDisplay;
	private ColorRect _fadeOverlay;
	private string _nextScene = "res://test.tscn";
	private bool _textureSet = false;
	private bool _isTransitioning = false;
	private float _fadeDuration = 1.0f; // Duration of fade in seconds
	private float _fadeProgress = 0.0f;
	
	public override void _Ready()
	{
		// Get the ACTUAL window size (not the viewport's base size)
		var windowSize = DisplayServer.WindowGetSize();
		
		GD.Print($"Window size: {windowSize}");
		GD.Print($"Viewport size: {GetViewportRect().Size}");
		
		// Set this control's size to match the window
		Size = windowSize;
		Position = Vector2.Zero;
		
		// Create VideoStreamPlayer
		_videoPlayer = new VideoStreamPlayer();
		AddChild(_videoPlayer);
		
		var videoStream = GD.Load<VideoStream>("res://Cutscenes/beggining ogg.ogv");
		
		if (videoStream == null)
		{
			GD.PrintErr("Failed to load video stream!");
			OnVideoFinished();
			return;
		}
		
		_videoPlayer.Stream = videoStream;
		_videoPlayer.Loop = false;
		_videoPlayer.Volume = 1.0f; // Use Volume property instead of VolumeDb
		_videoPlayer.Paused = false;
		
		// Create TextureRect for display
		_videoDisplay = new TextureRect();
		AddChild(_videoDisplay);
		
		// Use window size for the display
		_videoDisplay.Size = windowSize;
		_videoDisplay.Position = Vector2.Zero;
		_videoDisplay.ExpandMode = TextureRect.ExpandModeEnum.IgnoreSize;
		_videoDisplay.StretchMode = TextureRect.StretchModeEnum.KeepAspectCovered;
		
		// Create fade overlay (initially transparent)
		_fadeOverlay = new ColorRect();
		AddChild(_fadeOverlay);
		_fadeOverlay.Size = windowSize;
		_fadeOverlay.Position = Vector2.Zero;
		_fadeOverlay.Color = new Color(0, 0, 0, 0); // Black, fully transparent
		_fadeOverlay.MouseFilter = MouseFilterEnum.Ignore;
		
		_videoPlayer.Finished += OnVideoFinished;
		_videoPlayer.Play();
		
		GD.Print($"Video is playing: {_videoPlayer.IsPlaying()}");
	}
	
	public override void _Process(double delta)
	{
		if (_isTransitioning)
		{
			// Progress the fade
			_fadeProgress += (float)delta / _fadeDuration;
			_fadeProgress = Mathf.Clamp(_fadeProgress, 0.0f, 1.0f);
			
			// Fade to black
			_fadeOverlay.Color = new Color(0, 0, 0, _fadeProgress);
			
			// Fade audio (Volume property goes from 1.0 to 0.0)
			if (_videoPlayer != null)
			{
				_videoPlayer.Volume = 1.0f - _fadeProgress;
			}
			
			// Change scene when fade is complete
			if (_fadeProgress >= 1.0f)
			{
				GD.Print("Fade complete, changing scene");
				GetTree().ChangeSceneToFile(_nextScene);
			}
			
			return;
		}
		
		if (_videoPlayer != null && _videoPlayer.IsPlaying())
		{
			var texture = _videoPlayer.GetVideoTexture();
			
			if (texture != null)
			{
				_videoDisplay.Texture = texture;
				
				if (!_textureSet)
				{
					_textureSet = true;
					GD.Print($"Texture set! Size: {texture.GetSize()}");
					GD.Print($"Display size: {_videoDisplay.Size}");
				}
			}
		}
		
		// Allow skipping
		if (Input.IsActionJustPressed("ui_cancel") || Input.IsActionJustPressed("ui_accept"))
		{
			OnVideoFinished();
		}
	}
	
	private void OnVideoFinished()
	{
		if (_isTransitioning)
			return;
			
		GD.Print("Video finished, starting fade transition");
		_isTransitioning = true;
		_fadeProgress = 0.0f;
	}
}
