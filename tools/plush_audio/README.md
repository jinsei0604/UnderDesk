# Rebuilding the approved plush scream

Requires Python + NumPy and FFmpeg built with the Rubber Band filter.

`python tools/plush_audio/build_ghost_scream.py --ffmpeg <ffmpeg> --output <new-output-directory>`

The script writes an audition WAV and metadata to the requested output directory; it never replaces game assets. The output was approved as v12. Keep the approved WAV byte-identical unless a new edit is requested. Source and license: assets_bossmaker/battle/plush/v12/audio/LICENSE.md.
