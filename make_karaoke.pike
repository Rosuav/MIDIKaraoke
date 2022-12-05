object midilib = (object)"../shed/patchpatch.pike";

//Meta-event types
enum {TEXT = 0x01, LYRIC = 0x05, TEMPO = 0x51, TIMESIG = 0x58};

string pos_to_vtt(int pos, array timing, int timediv) {
	//The timing info has a base microsecond position, and the tempo
	int msec = (timing[1] + pos * timing[2] / timediv) / 1000;
	int sec = msec / 1000; msec %= 1000;
	int min = sec / 60; sec %= 60;
	int hr = min / 60; min %= 60;
	return sprintf("%02d:%02d:%02d.%03d", hr, min, sec, msec);
}

void make_karaoke(string fn, string outdir) {
	array(array(string|array(array(int|string)))) chunks = midilib->parsesmf(Stdio.read_file(fn));
	//write("%d %O\n", sizeof(chunks), chunks[2]);
	//According to the SMF Type 1 spec, the first track should have all the timing info.
	sscanf(chunks[0][1], "%2c%*2c%2c", int format, int timediv);
	if (format == 2) {werror("Can't handle Type 2 MIDI currently\n"); return;}
	//write("Timing: %d\n", timediv);
	int pos = 0; //Time since last tempo change
	int usec = 0; //Not guaranteed to be entirely accurate - it may lose up to one microsecond per tempo shift
	array timings = ({({0, 0, 500000})}); //Each entry is [delta-miditime, usec-base, tempo]
	foreach (chunks[1][1], array ev) {
		pos += ev[0];
		if (ev[1] == 0xFF && ev[2] == TEMPO) {
			sscanf(ev[3], "%3c", int tempo);
			usec += pos * timings[-1][2] / timediv;
			//write("[%d %d] Tempo: %d\n", pos, usec/1000, tempo);
			timings += ({({pos, usec, tempo})});
			pos = 0;
		}
	}
	timings += ({({1<<30, 0, 0})}); //Have a dummy timing entry that we'll never reach

	//Find the chunk with the most LYRIC entries. If none, use the chunk with the
	//most TEXT entries instead, since some files use text lyrics. It's like SPF.
	array besttext, bestlyrics;
	int ntextbest, nlyricsbest;
	foreach (chunks[1..], [string _, array track]) {
		int ntext, nlyrics;
		foreach (track, array ev) {
			if (ev[1] == 0xFF && ev[2] == TEXT) ++ntext;
			if (ev[1] == 0xFF && ev[2] == LYRIC) ++nlyrics;
		}
		if (nlyrics > nlyricsbest) {bestlyrics = track; nlyricsbest = nlyrics;}
		if (ntext > ntextbest) {besttext = track; ntextbest = ntext;}
	}
	array track = bestlyrics; int event = LYRIC;
	if (!track) {track = besttext; event = TEXT;}
	if (!track) track = ({ }); //No lyrics or even text. Quite unusual (there's normally at least some sort of descriptive info).
	pos = 0;
	int timingpos = 0; //Index into timings[]
	string start, line = "";
	Stdio.File vtt = Stdio.File(outdir + "temp.vtt", "wct");
	vtt->write("WEBVTT\n\n");
	track += ({({0, 0xFF, event, "\n"})}); //Hack: Ensure proper emission of final entry
	foreach (track, array ev) {
		pos += ev[0];
		while (pos >= timings[timingpos + 1][0]) {
			//We've reached (or passed) the next tempo change. (We might actually
			//pass more than one at once; an accelerando/ritando can be implemented
			//with multiple tempo markers, and may easily have no lyrics until done.)
			pos -= timings[++timingpos][0];
			//write("Tempo mark after %d, at usec %d\n", timings[timingpos][0], timings[timingpos][1]);
		}
		if (ev[1] == 0xFF && ev[2] == event) {
			string pending = "";
			if (has_value("/\\", ev[3][0])) {
				//Some lyrics mark the start of a line with a slash or backslash,
				//rather than marking the end of a line with a carriage return or
				//line feed. Process the line end first, and then put the text in
				//the buffer for later.
				pending = ev[3][1..];
				ev[3] = (['/': "\r", '\\': "\n"])[ev[3][0]]; //Currently it makes no difference, but I may in the future distinguish.
			}
			//write("[%d] %02X %s\n", pos, ev[2], replace(ev[3], (["\r": "<eol>", "\n": "<EOL>"])));
			string time = pos_to_vtt(pos, timings[timingpos], timediv);
			if (line == "") start = time;
			//else line += "<" + time + ">"; //Enable karaoke-style captions. Remove if not needed (eg if latency is going to be too strong)
			line += ev[3];
			if (has_value("\r\n", ev[3][-1])) {
				line = String.trim(line);
				if (line != "") vtt->write("%s --> %s\n%s\n\n", start, time, line);
				line = pending;
				start = time; //Will be overwritten by the next lyric entry's timestamp if pending was blank
			}
		}
	}
}

int main(int argc, array(string) argv) {
	foreach (argv[1..], string arg) make_karaoke(arg, "cache/");
}
