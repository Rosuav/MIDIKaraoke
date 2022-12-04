object midilib = (object)"../shed/patchpatch.pike";

void make_karaoke(string fn, string outdir) {
	array(array(string|array(array(int|string)))) chunks = midilib->parsesmf(Stdio.read_file(fn));
	//write("%d %O\n", sizeof(chunks), chunks[2]);
	//For now, assume that track #2 has the lyrics. TODO: Find the track with the most lyric events.
	//TODO: Also support TEXT (0x01) instead of lyrics (0x05)
	array track = chunks[2][1];
	int pos = 0;
	int start = 0; string line = "";
	foreach (track, array ev) {
		pos += ev[0];
		if (ev[1] == 0xFF && ev[2] == 0x05) {
			//write("[%d] %02X %s\n", pos, ev[2], replace(ev[3], (["\r": "<eol>", "\n": "<EOL>"])));
			if (line == "") start = pos;
			line += ev[3];
			if (has_value("\r\n", ev[3][-1])) {
				line = String.trim(line);
				if (line != "") write("[%d-%d] %s\n", start, pos, line);
				line = "";
			}
		}
	}
}

int main(int argc, array(string) argv) {
	foreach (argv[1..], string arg) make_karaoke(arg, "cache/");
}
