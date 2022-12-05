object midilib = (object)"../shed/patchpatch.pike";

//Meta-event types
enum {LYRIC = 0x05, TEMPO = 0x51, TIMESIG = 0x58};

int pos_to_usec(int pos, array timing, int timediv) {
	//The timing info has a base microsecond position, and the tempo
	return timing[1] + pos * timing[2] / timediv;
}

void make_karaoke(string fn, string outdir) {
	array(array(string|array(array(int|string)))) chunks = midilib->parsesmf(Stdio.read_file(fn));
	//write("%d %O\n", sizeof(chunks), chunks[2]);
	//According to the SMF Type 1 spec, the first track should have all the timing info.
	sscanf(chunks[0][1], "%2c%*2c%2c", int format, int timediv);
	if (format == 2) {werror("Can't handle Type 2 MIDI currently\n"); return;}
	write("Timing: %d\n", timediv);
	int pos = 0; //Time since last tempo change
	int usec = 0; //Not guaranteed to be entirely accurate - it may lose up to one microsecond per tempo shift
	array timings = ({({0, 0, 500000})}); //Each entry is [delta-miditime, usec-base, tempo]
	foreach (chunks[1][1], array ev) {
		pos += ev[0];
		if (ev[1] == 0xFF && ev[2] == TEMPO) {
			sscanf(ev[3], "%3c", int tempo);
			usec += pos * timings[-1][2] / timediv;
			write("[%d %d] Tempo: %d\n", pos, usec/1000, tempo);
			timings += ({({pos, usec, tempo})});
			pos = 0;
		}
	}
	timings += ({({1<<30, 0, 0})}); //Have a dummy timing entry that we'll never reach
	//For now, assume that track #2 has the lyrics. TODO: Find the track with the most lyric events.
	//TODO: Also support TEXT (0x01) instead of lyrics (0x05)
	array track = chunks[2][1];
	pos = 0;
	int timingpos = 0; //Index into timings[]
	int start = 0; string line = "";
	foreach (track, array ev) {
		pos += ev[0];
		while (pos >= timings[timingpos + 1][0]) {
			//We've reached (or passed) the next tempo change. (We might actually
			//pass more than one at once; an accelerando/ritando can be implemented
			//with multiple tempo markers, and may easily have no lyrics until done.)
			pos -= timings[++timingpos][0];
			write("Tempo mark after %d, at usec %d\n", timings[timingpos][0], timings[timingpos][1]);
		}
		if (ev[1] == 0xFF && ev[2] == LYRIC) {
			//write("[%d] %02X %s\n", pos, ev[2], replace(ev[3], (["\r": "<eol>", "\n": "<EOL>"])));
			if (line == "") start = pos_to_usec(pos, timings[timingpos], timediv);
			line += ev[3];
			if (has_value("\r\n", ev[3][-1])) {
				line = String.trim(line);
				if (line != "") write("[%d-%d] %s\n", start / 1000, pos_to_usec(pos, timings[timingpos], timediv) / 1000, line);
				line = "";
			}
		}
	}
	write("[%d] End of track\n", pos_to_usec(pos, timings[timingpos], timediv) / 1000);
}

int main(int argc, array(string) argv) {
	foreach (argv[1..], string arg) make_karaoke(arg, "cache/");
}
