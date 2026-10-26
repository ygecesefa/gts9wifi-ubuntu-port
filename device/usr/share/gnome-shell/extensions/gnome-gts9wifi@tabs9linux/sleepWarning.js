// SPDX-License-Identifier: MIT
//
// Drop gnome-settings-daemon's "Automatic suspend" warning.
//
// Some time before the idle suspend, gsd-power shows "Suspending soon because
// of inactivity" as a CRITICAL notification, which lit the tablet's dark
// screen; the screen coming on counted as activity, the idle timers started
// over, and the tablet went dark, lit up for the warning and went dark again
// instead of suspending.  gsd-power skips this warning itself on a "tablet"
// or "handset" chassis, but this one says "convertible" (/etc/machine-info:
// on "tablet" gsd-media-keys suspends on power-key down, before
// gts9wifi-power-key can tell a press from a hold).  So the warning is marked
// acknowledged as it arrives, before the message tray asks for its banner;
// the suspend itself still comes on time.  Low-battery notifications from
// the same source are not touched: only the title gsd-power uses for this
// warning, in the session's language, is matched.

import Gettext from 'gettext';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';

const GSD_DOMAIN = 'gnome-settings-daemon';
const TITLES = ['Automatic suspend', 'Automatic hibernation'];

export class SleepWarning {
    enable() {
        this._titles = new Set(TITLES.flatMap(t => [t, Gettext.dgettext(GSD_DOMAIN, t)]));
        this._sources = new Map();
        Main.messageTray.getSources().forEach(s => this._watch(s));
        this._addedId = Main.messageTray.connect('source-added',
            (_tray, source) => this._watch(source));
    }

    _watch(source) {
        if (this._sources.has(source))
            return;
        const id = source.connect('notification-added', (_source, notification) => {
            if (this._titles.has(notification.title))
                notification.acknowledged = true;
        });
        const destroyId = source.connect('destroy', () => this._sources.delete(source));
        this._sources.set(source, [id, destroyId]);
    }

    disable() {
        if (this._addedId)
            Main.messageTray.disconnect(this._addedId);
        this._addedId = 0;
        for (const [source, ids] of this._sources)
            ids.forEach(id => source.disconnect(id));
        this._sources?.clear();
    }
}
