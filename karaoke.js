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
