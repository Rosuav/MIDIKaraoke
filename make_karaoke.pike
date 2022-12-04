object midilib = (object)"patchpatch.pike";

void make_karaoke(string fn, string outdir) {
	
}

int main(int argc, array(string) argv) {
	foreach (argv[1..], string arg) make_karaoke(arg, "cache/");
}
