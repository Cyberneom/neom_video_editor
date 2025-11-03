### 1.4.0 Initial Release & Foundational Video Editing Capabilities
This marks the initial official release (v1.0.0) of neom_video_editor as a new, independent module within the Open Neom ecosystem. This module is introduced to provide essential video editing functionalities, laying the groundwork for a comprehensive media manipulation suite.

Key Highlights of this Release:

New Module Introduction:

neom_video_editor is now a dedicated module for all video editing processes, ensuring a clear separation of concerns from other media-related functionalities (e.g., neom_media_upload).

This aligns with Open Neom's modular architecture, promoting specialized development and maintainability.

Core Video Editing Features:

Video Trimming: Implements precise control over video duration, allowing users to select start and end points for their clips.

Video Cropping: Provides functionality to adjust the aspect ratio and frame of video content.

Utilizes external libraries like video_editor, easy_video_editor, and video_compress for robust video processing.

Future-Proof Design:

While this version focuses on foundational trimming and cropping, the module is designed with extensibility in mind. It is envisioned to evolve into an advanced video editing platform, similar to popular social media tools (e.g., TikTok, Instagram Reels), by incorporating filters, effects, text overlays, and more in future releases.

Integration with Core Open Neom Modules:

Built upon neom_core for foundational services (like UserService for user role-based limits on video duration) and neom_commons for reusable UI components and utilities, ensuring seamless integration within the ecosystem.akes the module easier to understand, debug, and extend for future features.ental services and data models, and `neom_commons` for shared UI components, ensuring consistency and efficiency across the platform.