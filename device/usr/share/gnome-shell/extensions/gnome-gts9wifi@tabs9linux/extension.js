// SPDX-License-Identifier: MIT
//
// All of this extension's UI is its settings page (prefs.js), which is where
// the device-specific controls live.  There is deliberately no panel or Quick
// Settings presence: these are set-once controls rather than something worth
// toggling from the top bar, and on a tablet a stray panel toggle is easy to
// hit by accident.
//
// The extension also has to be enabled for its settings page to be reachable
// from the Extensions app.  Its one runtime job is oskFocus.js: open the
// on-screen keyboard for touch-focused text fields of Chromium-based apps.

import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';

import {OskFocus} from './oskFocus.js';

export default class Gts9wifiExtension extends Extension {
    enable() {
        this._oskFocus = new OskFocus();
        this._oskFocus.enable();
    }

    disable() {
        this._oskFocus?.disable();
        this._oskFocus = null;
    }
}
