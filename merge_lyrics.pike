//Take a non-karaoke MIDI file and merge lyrics into it
object midilib = (object)"../shed/patchpatch.pike";

string pos_to_vtt(int pos, array timing, int timediv) {
	//The timing info has a base microsecond position, and the tempo
	int msec = (timing[1] + pos * timing[2] / timediv) / 1000;
	int sec = msec / 1000; msec %= 1000;
	int min = sec / 60; sec %= 60;
	int hr = min / 60; min %= 60;
	return sprintf("%02d:%02d:%02d.%03d", hr, min, sec, msec);
}

Regexp.SimpleRegexp slugify = Regexp.SimpleRegexp("[^a-zA-Z0-9]+");

void merge_lyrics(string midifile, string lyricfile) {
	array(array(string|array(array(int|string)))) chunks = midilib->parsesmf(Stdio.read_file(midifile));
	sscanf(chunks[0][1], "%2c%*2c%2c", int format, int timediv);
	if (format == 2) {werror("Can't handle Type 2 MIDI currently\n"); return;}

	foreach (chunks[1..], [string _, array track]) {
		write("Track\n=====\n");
		int lastchan = -1;
		foreach (track, array ev) {
			if (ev[1] == 0xFF && ev[2] == 3) write("Title: %s\n", ev[3]);
			if (ev[1] == lastchan && ev[0] == 0) {
				write("+ c%d note %d\n", ev[1] & 15, ev[2]); //Chord (multiple notes struck simultaneously)
				continue;
			}
			if (ev[1] >= 0x90 && ev[1] <= 0x9F && ev[3]) {
				write("c%d note %d\n", ev[1] & 15, ev[2]);
				lastchan = ev[1];
			}
			else lastchan = -1;
		}
	}
	return;
}

int main(int argc, array(string) argv) {
	merge_lyrics(argv[1], argv[2]);
	return 0;
}
