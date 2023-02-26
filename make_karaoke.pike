//Possibly badly-named; this makes a VTT from a MIDI Karaoke file.
object midilib = (object)"../shed/patchpatch.pike";
constant VLC_EXTENSION_PATH = "~/.local/share/vlc/lua/extensions"; //TODO: How would this work on other platforms??

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

Regexp.SimpleRegexp slugify = Regexp.SimpleRegexp("[^a-zA-Z0-9]+");

string make_karaoke(string fn, string outdir) {
	string slug = slugify->replace(fn, "_");
	string outfn = outdir + slug + ".vtt";
	if (file_stat(outfn)) return outfn;
	array(array(string|array(array(int|string)))) chunks = midilib->parsesmf(Stdio.read_file(fn));
	//write("%d %O\n", sizeof(chunks), chunks[2]);
	//According to the SMF Type 1 spec, the first track should have all the timing info.
	sscanf(chunks[0][1], "%2c%*2c%2c", int format, int timediv);
	if (format == 2) {werror("Can't handle Type 2 MIDI currently\n"); return outfn;}
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
	Stdio.File vtt = Stdio.File(outfn, "wct");
	string ogg = replace(fn, ([".kar": ".ogg", ".mid": ".ogg", ".midi": ".ogg"]));
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
			if (event == TEXT && has_prefix(ev[3], "@")) continue; //Files that use text lyrics also seem to encode metadata with "@<letter><info>" format.
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
				catch {line = utf8_to_string(line);}; //Attempt UTF-8, if not, assume ISO-8859-1
				if (line != "") vtt->write("%s --> %s\n%s\n\n", start, time, string_to_utf8(line));
				line = pending;
				start = time; //Will be overwritten by the next lyric entry's timestamp if pending was blank
			}
		}
	}
	return outfn;
}

void send(Protocols.WebSocket.Connection conn, mapping msg) {
	conn->send_text(Standards.JSON.encode(msg));
}

string authkey = "";
void websocket_init(object conn) {
	write("Websocket connected.\n");
	send(conn, (["cmd": "init", "type": "chan_vlc", "group": authkey + "#rosuav"])); //TODO: Let the channel be configurable
}

void msg(Protocols.WebSocket.Frame frm, object conn) {
	mixed data;
	if (catch {data = Standards.JSON.decode(frm->text);}) return;
	if (!mappingp(data)) return;
	if (data->cmd == "update") {
		if (data->filename != "") {
			object uri = Standards.URI(data->filename);
			string fn = uri->path;
			array files = get_dir(dirname(fn));
			//Assuming here that the original file name is the same as the current, with
			//just the part after the (only) dot being changed. If the original file had
			//multiple dots, Timidity will have replaced them with underscores. A better
			//way to recover the original file name would be to query the OGG metadata -
			//this is created by Timidity and has LOCATION set to the original file. I'm
			//not sure what to do with non-OGG files though. FLAC and WAV don't work.
			sscanf(basename(fn), "%s.", string base);
			files = glob(base + ".*", files);
			base = lower_case(base);
			string midi;
			foreach (({".kar", ".mid", ".midi"}), string ext) {
				foreach (files, string f) if (lower_case(f) == base + ext) midi = f;
			}
			if (!midi) return;
			string webvtt = make_karaoke(dirname(fn) + "/" + midi, "cache/");
			string hash = String.string2hex(Crypto.SHA1.hash(fn));
			write("%O -> %O (was %O)\n", fn, hash, data->curnamehash);
			if (hash != data->curnamehash) send(conn, ([
				"cmd": "karaoke", "namehash": hash,
				//Not sending the raw audio data at this time.
				"audiotype": "audio/ogg", //TODO: give other MIME types as appropriate
				"webvttdata": Stdio.read_file(webvtt),
			]));
			return;
		}
	}
	if (data->cmd == "requestaudio") {
		object uri = Standards.URI(data->uri);
		string fn = uri->path;
		string hash = String.string2hex(Crypto.SHA1.hash(fn));
		string audiodata = "";
		if (hash == data->hash) audiodata = Stdio.read_file(fn);
		send(conn, ([
			"cmd": "provideaudio", "namehash": hash,
			"audiodata": audiodata,
		]));
		return;
	}
	write("Got message: %O\n", data);
}

int main(int argc, array(string) argv) {
	if (argc > 1) {
		foreach (argv[1..], string arg) make_karaoke(arg, "cache/");
		return 0;
	}
	//Intended logic:
	//1) On startup, find out what song is playing, and make_karaoke that song
	//2) On song change signal, make_karaoke the new song
	//3) Periodically check song position
	//4) On pause/play/stop, pass the signal along
	string lua = Stdio.read_file(replace(VLC_EXTENSION_PATH, "~", System.get_home()) + "/vlcstillebot.lua");
	sscanf(lua || "", "%*s?auth=%[^\n&]&", string key);
	authkey = key || "";
	object conn = Protocols.WebSocket.Connection();
	conn->onopen = websocket_init;
	conn->onmessage = msg;
	//TODO: Disconnect hook
	conn->connect("wss://sikorsky.rosuav.com/ws");
	return -1;
}
