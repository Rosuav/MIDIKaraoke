MIDI Karoke experiments
=======================

Playing around with HTML5 Audio and its subtitling/captioning abilities.

Ultimate goal:

* When a user requests "what's playing?", provide the info live.
* This requires making a way to mute the audio and keep the subtitles going.
* Ask VLC what's playing. It'll often be an OGG. Look in that directory for
  either a KAR or a MID of the same name, and be aware it could be ".kar" or
  ".KAR" depending on where the file came from.
* Check the cache to see if we have it. If not:
  - Parse the MIDI file
  - Render to OGG? Or use what VLC is already using?
  - Write out a VTT subtitles file - practically the same as SRT
* Render the default HTML page and link to the websocket.

Next steps:

* Migrate test.html and karaoke.{js,css} into StilleBot, thus removing the need
  for cross-origin permissions
* Link to the websocket and fetch new audio on the basis of the provided hash
  - The websocket may need to get the hash provided to it
* Synchronize timings. <== big one
* Synchronize play/pause status, but only if audio is untouched.
  - It should be perfectly reasonable to pause the audio, unmute it, etc; this
    should disconnect you from all synchronization.
  - Need a way to say "resume" - resync immediately and then stay in sync.
