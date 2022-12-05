import {choc, set_content, on, DOM} from "https://rosuav.github.io/choc/factory.js";
const {LI} = choc; //autoimport
function dumpcues(e) {
	if (e.target.readyState < 2) return;
	const cues = [...e.target.track.cues];
	set_content("#lyrics", cues.map(c => {
		const li = LI(c.text);
		c.onenter = () => {li.classList.add("active"); li.scrollIntoView({block: "nearest"});}
		c.onexit = () => li.classList.remove("active");
		return li;
	}));
}
document.querySelectorAll("track").forEach(t => {
	if (t.readyState < 2) t.onload = dumpcues;
	else dumpcues({target: t});
});
//Force full preloading of the audio data. This allows seeking, even if the
//backend server doesn't support byte-range requests. I'm a bit confused as
//to why this is a hard requirement, since the audio data in question isn't
//particularly large (under 10MB), so it ought to be possible to preload it
//(although preload="auto" doesn't guarantee that) and then seek. Whatever.
document.querySelectorAll("audio,video").forEach(aud => {
	fetch(aud.dataset.src).then(r => r.blob())
	.then(blob => aud.src = URL.createObjectURL(blob));
});
