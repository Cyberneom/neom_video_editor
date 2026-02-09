# neom_video_editor

A professional-grade video editing module for Flutter applications, part of the Open Neom ecosystem. Designed to compete with industry-leading video editors like CapCut, InShot, and Adobe Premiere Rush.

## Current Version: 1.2.0

## Features

### Current Capabilities (v1.2.0)
- **Video Trimming**: Precise start/end point selection with visual timeline
- **Video Cropping**: Aspect ratio adjustment for different platforms
- **Progress Indication**: Real-time export progress tracking
- **Role-Based Limits**: Configurable video duration limits by user role
- **FFmpeg Integration**: Professional-grade video processing

## Installation

```yaml
dependencies:
  neom_video_editor:
    git:
      url: git@github.com:Cyberneom/neom_video_editor.git
```

## Usage

```dart
import 'package:neom_video_editor/video_editor/video_editor_routes.dart';

// Navigate to video editor
Navigator.push(context, MaterialPageRoute(
  builder: (_) => VideoEditorPage(videoFile: file),
));
```

---

## ROADMAP 2026: Professional Video Editor

Our vision is to transform neom_video_editor into a **world-class video editing solution** capable of competing with TikTok, CapCut, and professional mobile editors.

### Q1 2026: Core Editing Enhancement

#### Timeline & Navigation
- [ ] **Multi-track Timeline** - Visual multi-layer editing interface
- [ ] **Zoom & Scroll** - Precise timeline navigation
- [ ] **Keyframe Animation** - Property animation over time
- [ ] **Undo/Redo Stack** - Full edit history (50+ levels)
- [ ] **Auto-save & Recovery** - Prevent work loss

#### Trimming & Cutting
- [ ] **Split Tool** - Cut clips at any point
- [ ] **Multi-select** - Select and edit multiple clips
- [ ] **Ripple Delete** - Auto-close gaps after deletion
- [ ] **Slip & Slide Editing** - Non-destructive clip adjustment
- [ ] **Frame-by-Frame Navigation** - Precise editing control

#### Speed Control
- [ ] **Speed Ramp** - Smooth acceleration/deceleration
- [ ] **Slow Motion** - 0.1x to 1x with frame interpolation
- [ ] **Fast Motion** - 1x to 16x speed increase
- [ ] **Reverse Playback** - Play clips backwards
- [ ] **Time Freeze** - Hold frame effect

### Q2 2026: Visual Effects & Filters

#### Professional Filters
- [ ] **Cinematic LUTs** - 50+ Hollywood-grade color grading
- [ ] **Filter Categories**: Vintage, Modern, B&W, Neon, Film
- [ ] **Filter Intensity** - Adjustable strength slider
- [ ] **Custom LUT Import** - Support .cube files
- [ ] **Real-time Preview** - Instant filter application

#### Color Correction
- [ ] **Color Wheels** - Shadows, midtones, highlights
- [ ] **Curves** - RGB and luminance curves
- [ ] **HSL Adjustment** - Per-color fine tuning
- [ ] **White Balance** - Temperature and tint
- [ ] **Exposure & Contrast** - Professional controls

#### Visual Effects
- [ ] **Blur Effects**: Gaussian, motion, radial, directional
- [ ] **Glitch Effects** - Digital distortion pack
- [ ] **Light Leaks** - Cinematic light overlays
- [ ] **Lens Flare** - Anamorphic and standard
- [ ] **Shake Effect** - Camera shake simulation
- [ ] **Zoom Effects** - Ken Burns, punch zoom

### Q3 2026: Audio & Sound Design

#### Audio Editing
- [ ] **Waveform Visualization** - Visual audio editing
- [ ] **Volume Keyframes** - Animated volume changes
- [ ] **Audio Fade** - Fade in/out transitions
- [ ] **Audio Ducking** - Auto-lower music during speech
- [ ] **Noise Reduction** - AI-powered noise removal

#### Music & Sound
- [ ] **Royalty-Free Music Library** - 500+ tracks
- [ ] **Sound Effects Library** - 1000+ categorized SFX
- [ ] **Beat Detection** - Auto-sync to music beats
- [ ] **Voiceover Recording** - In-app voice capture
- [ ] **Voice Changer** - Pitch and effect modification

### Q4 2026: Creative Tools & AI

#### Text & Titles
- [ ] **Animated Text** - 50+ animation presets
- [ ] **Title Templates** - Social media ready
- [ ] **Subtitle Generator** - Manual and AI-assisted
- [ ] **Text Tracking** - Text follows motion
- [ ] **3D Text** - Depth and perspective

#### Stickers & Overlays
- [ ] **Animated Stickers** - 1000+ motion graphics
- [ ] **Emoji & GIF** - Searchable library
- [ ] **Custom Import** - PNG, GIF, video overlays
- [ ] **Picture-in-Picture** - Video layering
- [ ] **Green Screen** - Chroma key removal

#### AI-Powered Features
- [ ] **Auto-Cut** - AI scene detection and cutting
- [ ] **Auto-Caption** - Speech-to-text subtitles
- [ ] **Background Removal** - AI video background extraction
- [ ] **Object Tracking** - Auto-follow subjects
- [ ] **Smart Resize** - AI-powered aspect ratio conversion
- [ ] **Face Detection** - Auto-zoom on faces
- [ ] **Style Transfer** - Apply artistic styles to video

### Transitions Library

#### Basic Transitions
- [ ] Cut, Dissolve, Fade, Wipe

#### Creative Transitions
- [ ] **Zoom Transitions** - Zoom in/out between clips
- [ ] **Spin Transitions** - Rotation effects
- [ ] **Glitch Transitions** - Digital distortion
- [ ] **Luma/RGB Transitions** - Color-based blending
- [ ] **Swipe Transitions** - Directional reveals
- [ ] **Custom Duration** - Adjustable timing

### Export & Sharing

#### Export Options
- [ ] **Resolution**: 480p to 4K
- [ ] **Frame Rate**: 24, 30, 60 FPS
- [ ] **Codec Selection** - H.264, H.265/HEVC
- [ ] **Bitrate Control** - Quality vs size
- [ ] **Format Options** - MP4, MOV, WebM

#### Platform Presets
- [ ] **TikTok** - 9:16, optimized settings
- [ ] **Instagram Reels** - 9:16, 1080x1920
- [ ] **YouTube Shorts** - 9:16, max quality
- [ ] **YouTube** - 16:9, 4K support
- [ ] **Twitter/X** - Optimized compression
- [ ] **Custom Presets** - Save personal export settings

### Technical Architecture Goals

```
lib/
├── core/
│   ├── engine/
│   │   ├── video_processor.dart      # FFmpeg wrapper
│   │   ├── render_engine.dart        # GPU-accelerated rendering
│   │   ├── timeline_engine.dart      # Multi-track composition
│   │   └── audio_engine.dart         # Audio processing
│   ├── ai/
│   │   ├── scene_detection.dart      # Auto-cut AI
│   │   ├── speech_to_text.dart       # Auto-caption
│   │   ├── background_removal.dart   # Video segmentation
│   │   └── object_tracking.dart      # Motion tracking
│   └── utils/
│       ├── codec_utils.dart          # Video codec handling
│       └── thumbnail_generator.dart  # Preview generation
├── features/
│   ├── timeline/                     # Timeline UI & logic
│   ├── trimming/                     # Trim & cut tools
│   ├── filters/                      # Color grading & filters
│   ├── effects/                      # Visual effects
│   ├── audio/                        # Audio editing
│   ├── text/                         # Titles & captions
│   ├── transitions/                  # Transition library
│   ├── stickers/                     # Overlays & stickers
│   └── export/                       # Export system
└── ui/
    ├── editor_page.dart              # Main editor interface
    ├── timeline_view.dart            # Timeline component
    ├── preview_player.dart           # Video preview
    └── tools_panel.dart              # Tool selection
```

### Performance Targets
- **Preview Playback**: 30+ FPS during editing
- **Scrubbing**: <100ms latency
- **Export Speed**: Real-time or faster
- **Memory Usage**: <500MB for 1080p projects
- **Battery Efficiency**: Optimized for mobile
- **Startup Time**: <1s cold start

### Competitive Analysis

| Feature | neom_video_editor (2026) | CapCut | InShot | Premiere Rush |
|---------|--------------------------|--------|--------|---------------|
| Multi-track Timeline | Yes | Yes | Limited | Yes |
| Keyframe Animation | Yes | Yes | No | Yes |
| AI Auto-Caption | Yes | Yes | No | Yes |
| AI Background Removal | Yes | Yes | No | Yes (cloud) |
| Music Library | 500+ | 1000+ | 500+ | Limited |
| Custom LUT Import | Yes | Yes | No | Yes |
| 4K Export | Yes | Yes | Yes | Yes |
| Offline Processing | Yes | Partial | Yes | No |
| Open Source | Yes | No | No | No |

---

## Dependencies

- `neom_core` - Core services and configuration
- `neom_commons` - Shared UI components
- `video_editor` - Video editing UI components
- `easy_video_editor` - FFmpeg-based video processing
- `video_compress` - Video compression utilities
- `fraction` - Aspect ratio calculations

## License

Apache License 2.0 - see [LICENSE](LICENSE) for details.

---

**Open Neom** - Empowering digital expression through open-source technology.
