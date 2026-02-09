# Changelog

All notable changes to neom_video_editor will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.2.0] - 2025-02-08

### Changed
- **Updated README**: Complete rewrite with ambitious ROADMAP 2026 for professional-grade video editing
- Version bump to align with ecosystem releases

### Documentation
- Added comprehensive ROADMAP 2026 with quarterly milestones
- Added competitive analysis vs CapCut, InShot, Premiere Rush
- Added technical architecture goals
- Added performance targets
- Added export options and platform presets documentation

### ROADMAP 2026 Highlights
- Q1: Core editing (multi-track timeline, keyframes, speed control)
- Q2: Visual effects & filters (50+ LUTs, color correction, effects)
- Q3: Audio & sound design (music library, beat detection, voice effects)
- Q4: AI features (auto-cut, auto-caption, background removal)

## [1.1.0] - Previous Release

### Added
- Improved trimming precision
- Better progress indication during export
- User role-based video duration limits

### Fixed
- Export stability improvements
- Memory optimization for longer videos

## [1.0.0] - Initial Release

### Added

#### Module Introduction
- Dedicated module for video editing processes
- Clear separation from media upload and selection modules
- Modular architecture for easy extension

#### Core Features
- **Video Trimming**: Precise start/end point selection
  - Visual timeline interface
  - Frame-accurate trimming
  - Real-time preview
- **Video Cropping**: Aspect ratio adjustment
  - Square (1:1)
  - Portrait (9:16)
  - Landscape (16:9)
  - Custom ratios
- **Progress Indication**: Real-time export tracking
- **Role-Based Limits**: Configurable video duration by user role

#### Technical
- Uses `video_editor` for UI components
- Uses `easy_video_editor` for FFmpeg processing
- Uses `video_compress` for output optimization
- Built on `neom_core` and `neom_commons`

#### Future-Proof Design
- Extensible architecture for filters, effects, and overlays
- Designed to evolve into TikTok/CapCut-level editing suite
