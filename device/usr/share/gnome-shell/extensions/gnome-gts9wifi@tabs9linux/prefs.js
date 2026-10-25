// SPDX-License-Identifier: MIT
//
// The extension's own settings page, reachable from the Extensions app or with
//   gnome-extensions prefs gnome-gts9wifi@tabs9linux
//
// The page is built from whatever the helper reports, grouped by the group
// field it carries, so a new control shows up here without touching this file.

import Adw from 'gi://Adw';
import Gio from 'gi://Gio';

import {ExtensionPreferences, gettext as _} from 'resource:///org/gnome/Shell/Extensions/js/extensions/prefs.js';

import {helperAvailable, listControls, setControl} from './deviceControls.js';

export default class Gts9wifiPreferences extends ExtensionPreferences {
    fillPreferencesWindow(window) {
        const page = new Adw.PreferencesPage({
            title: _('Device controls'),
            icon_name: 'preferences-system-symbolic',
        });

        const controls = helperAvailable() ? listControls() : [];
        if (controls.length === 0) {
            const group = new Adw.PreferencesGroup();
            group.add(new Adw.ActionRow({
                title: _('No device controls found'),
                subtitle: _('This extension only does anything on the Galaxy Tab S9 Wi-Fi (SM-X710) Linux ports.'),
            }));
            page.add(group);
            window.add(page);
            return;
        }

        const groups = new Map();
        for (const control of controls) {
            if (!groups.has(control.group)) {
                const group = new Adw.PreferencesGroup({title: control.group});
                groups.set(control.group, group);
                page.add(group);
            }

            const row = new Adw.SwitchRow({
                title: control.label,
                subtitle: control.description,
                active: control.enabled,
            });

            // Reverting `active` after a refusal re-emits this signal, so guard
            // against recursing into it.
            let reverting = false;
            row.connect('notify::active', () => {
                if (reverting)
                    return;
                if (setControl(control.name, row.active))
                    return;

                reverting = true;
                row.active = !row.active;
                reverting = false;
            });

            groups.get(control.group).add(row);
        }

        page.add(this._lockGroup());
        page.add(this._keyboardGroup());
        window.add(page);
    }

    // GNOME's own lock settings: lock-enabled covers the screen blanking after
    // idle, Ubuntu's ubuntu-lock-on-suspend the suspend; gts9wifi-power-key
    // reads lock-enabled and does not lock before suspending when it is off.
    _lockGroup() {
        const group = new Adw.PreferencesGroup({title: _('Screen lock')});
        this._screensaver = new Gio.Settings({schema_id: 'org.gnome.desktop.screensaver'});
        // Off by default (GNOME's default: lock-enabled true).
        const row = new Adw.SwitchRow({
            title: _('Wake without the password'),
            subtitle: _('The password is asked once, at login: after that the power key and the screen timeout only turn the screen off, and waking goes straight back to the desktop.'),
        });
        this._screensaver.bind('lock-enabled', row, 'active',
            Gio.SettingsBindFlags.DEFAULT | Gio.SettingsBindFlags.INVERT_BOOLEAN);
        row.connect('notify::active', () => {
            if (this._screensaver.settings_schema.has_key('ubuntu-lock-on-suspend'))
                this._screensaver.set_boolean('ubuntu-lock-on-suspend', !row.active);
        });
        group.add(row);
        return group;
    }

    _keyboardGroup() {
        const group = new Adw.PreferencesGroup({title: _('Keyboard')});
        const row = new Adw.SwitchRow({
            title: _('Floating keyboard button'),
            subtitle: _('A draggable button that opens the on-screen keyboard, for apps that do not open it on their own (X11 apps, Wine).'),
        });
        this.getSettings().bind('keyboard-button', row, 'active',
            Gio.SettingsBindFlags.DEFAULT);
        group.add(row);
        return group;
    }
}
