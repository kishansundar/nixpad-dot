// Now playing: a tab paused for a minute stops being the one Zen announces, so the bar follows the tab that still plays (Zen's own value is 24 hours)
user_pref("media.mediacontrol.stopcontrol.timer.ms", 60000);
// Compact mode: the sidebar stays 0.6 s after the pointer leaves it and 3 s after the pointer goes off the screen edge (Zen's own values are 0.15 s and 1 s)
user_pref("zen.view.compact.sidebar-keep-hover.duration", 600);
user_pref("zen.view.compact.toolbar-hide-after-hover.duration", 3000);
