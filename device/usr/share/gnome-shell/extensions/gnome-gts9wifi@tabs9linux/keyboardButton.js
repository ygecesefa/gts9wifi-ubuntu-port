// SPDX-License-Identifier: MIT
//
// A small floating button that opens and closes GNOME's on-screen keyboard.
//
// Tapping a text field opens the keyboard in apps that speak Wayland
// text-input (see oskFocus.js), but X11 apps under XWayland and Wine never
// tell the shell that a field has focus.  The keyboard itself still types
// into them: it sends its keys through a virtual keyboard device.  So the
// button only has to open it.  Drag the button to move it; the position is
// kept as fractions of the monitor so it survives rotation.

import Clutter from 'gi://Clutter';
import GLib from 'gi://GLib';
import St from 'gi://St';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';

const SIZE = 56;
const MARGIN = 8;
const DRAG_THRESHOLD = 12;

export class KeyboardButton {
    constructor(settings) {
        this._settings = settings;
    }

    enable() {
        this._settingsId = this._settings.connect('changed::keyboard-button',
            () => this._sync());
        this._sync();
    }

    disable() {
        if (this._settingsId)
            this._settings.disconnect(this._settingsId);
        this._settingsId = 0;
        this._destroyButton();
    }

    _sync() {
        if (this._settings.get_boolean('keyboard-button'))
            this._createButton();
        else
            this._destroyButton();
    }

    _createButton() {
        if (this._button)
            return;

        this._button = new St.Widget({
            reactive: true,
            track_hover: true,
            width: SIZE,
            height: SIZE,
            layout_manager: new Clutter.BinLayout(),
            style: `border-radius: ${SIZE / 2}px;` +
                'background-color: rgba(40, 40, 40, 0.55);' +
                'border: 1px solid rgba(255, 255, 255, 0.25);',
        });
        this._button.add_child(new St.Icon({
            icon_name: 'input-keyboard-symbolic',
            icon_size: 28,
            style: 'color: white;',
            x_align: Clutter.ActorAlign.CENTER,
            y_align: Clutter.ActorAlign.CENTER,
        }));
        this._button.connect('event', (actor, event) => this._onEvent(event));

        Main.layoutManager.addTopChrome(this._button, {trackFullscreen: true});
        this._monitorsId = Main.layoutManager.connect('monitors-changed',
            () => this._place());
        this._place();
    }

    _destroyButton() {
        if (this._monitorsId)
            Main.layoutManager.disconnect(this._monitorsId);
        this._monitorsId = 0;
        this._grab?.dismiss();
        this._grab = null;
        if (this._button) {
            Main.layoutManager.removeChrome(this._button);
            this._button.destroy();
        }
        this._button = null;
    }

    _area() {
        const monitor = Main.layoutManager.primaryMonitor;
        return {
            x: monitor.x + MARGIN,
            y: monitor.y + MARGIN,
            w: Math.max(1, monitor.width - SIZE - 2 * MARGIN),
            h: Math.max(1, monitor.height - SIZE - 2 * MARGIN),
        };
    }

    _place() {
        if (!this._button || !Main.layoutManager.primaryMonitor)
            return;
        const [fx, fy] = this._settings.get_value('keyboard-button-position')
            .deepUnpack();
        const area = this._area();
        this._button.set_position(
            Math.round(area.x + Math.min(Math.max(fx, 0), 1) * area.w),
            Math.round(area.y + Math.min(Math.max(fy, 0), 1) * area.h));
    }

    _savePosition() {
        const area = this._area();
        const [x, y] = this._button.get_position();
        this._settings.set_value('keyboard-button-position',
            new GLib.Variant('(dd)', [
                Math.min(Math.max((x - area.x) / area.w, 0), 1),
                Math.min(Math.max((y - area.y) / area.h, 0), 1),
            ]));
    }

    _onEvent(event) {
        const type = event.type();
        const press = type === Clutter.EventType.BUTTON_PRESS ||
            type === Clutter.EventType.TOUCH_BEGIN;
        const motion = type === Clutter.EventType.MOTION ||
            type === Clutter.EventType.TOUCH_UPDATE;
        const release = type === Clutter.EventType.BUTTON_RELEASE ||
            type === Clutter.EventType.TOUCH_END ||
            type === Clutter.EventType.TOUCH_CANCEL;

        if (press) {
            const [px, py] = event.get_coords();
            const [bx, by] = this._button.get_position();
            this._press = {px, py, bx, by, dragging: false};
            this._grab = global.stage.grab(this._button);
            return Clutter.EVENT_STOP;
        }
        if (!this._press)
            return Clutter.EVENT_PROPAGATE;

        if (motion) {
            const [px, py] = event.get_coords();
            const dx = px - this._press.px, dy = py - this._press.py;
            if (!this._press.dragging && Math.hypot(dx, dy) > DRAG_THRESHOLD)
                this._press.dragging = true;
            if (this._press.dragging) {
                const area = this._area();
                this._button.set_position(
                    Math.min(Math.max(this._press.bx + dx, area.x), area.x + area.w),
                    Math.min(Math.max(this._press.by + dy, area.y), area.y + area.h));
            }
            return Clutter.EVENT_STOP;
        }
        if (release) {
            this._grab?.dismiss();
            this._grab = null;
            const dragged = this._press.dragging;
            this._press = null;
            if (dragged)
                this._savePosition();
            else if (type !== Clutter.EventType.TOUCH_CANCEL)
                this._toggleKeyboard();
            return Clutter.EVENT_STOP;
        }
        return Clutter.EVENT_PROPAGATE;
    }

    _toggleKeyboard() {
        const keyboard = Main.keyboard;
        if (keyboard.visible)
            keyboard.close();
        else
            keyboard.open(Main.layoutManager.primaryIndex);
    }
}
