MIDI Karoke for StilleBot
=========================

Links with the StilleBot VLC integration and provides subtitles/captions with
song lyrics derived from MIDI Karaoke files.

The bot drives everything and is the sole information broker. When the lyric
engine starts up, it queries the bot for status (which will have come from
VLC), then locates the MIDI file that this was derived from. Assuming it can
find it, it then parses the file, locates the lyrics, generates a WEBVTT file,
and sends that to StilleBot. It can also provide the audio file itself, but
does so only on request, to avoid spamming megabytes of unwanted audio data.

Timing synchronization is handled by StilleBot directly.
