// SPDX-License-Identifier: MIT
//
// Open the on-screen keyboard when a text field gains focus from a touch.
//
// Mutter 46 only asks for the keyboard when a Wayland client sends
// text-input-v3 "enable" a second time while its field is already focused.
// GTK does that on every tap; Chromium (and Electron apps) enable once per
// focus, so their fields never bring the keyboard up.  The shell's input
// method focus-in is seen here through two of its helpers (_fullReset runs
// on focus-out, _emitRequestSurrounding on focus-in), and the panel is
// requested when the last input came from the touchscreen.

import Clutter from 'gi://Clutter';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';

export class OskFocus {
    enable() {
        const im = Main.inputMethod;
        if (typeof im._emitRequestSurrounding !== 'function' ||
            typeof im._fullReset !== 'function')
            return;

        this._focused = Boolean(im._currentFocus);
        this._origEmit = im._emitRequestSurrounding;
        this._origReset = im._fullReset;
        const self = this;

        im._emitRequestSurrounding = function (...args) {
            const ret = self._origEmit.apply(this, args);
            if (this._currentFocus && !self._focused) {
                self._focused = true;
                if (self._lastInputWasTouch())
                    this.set_input_panel_state(Clutter.InputPanelState.ON);
            }
            return ret;
        };
        im._fullReset = function (...args) {
            if (!this._currentFocus)
                self._focused = false;
            return self._origReset.apply(this, args);
        };
    }

    disable() {
        const im = Main.inputMethod;
        if (this._origEmit)
            im._emitRequestSurrounding = this._origEmit;
        if (this._origReset)
            im._fullReset = this._origReset;
        this._origEmit = this._origReset = null;
    }

    _lastInputWasTouch() {
        const keyboard = Main.keyboard;
        if (typeof keyboard?._lastDeviceIsTouchscreen === 'function')
            return keyboard._lastDeviceIsTouchscreen();
        return Clutter.get_default_backend().get_default_seat().touch_mode;
    }
}
