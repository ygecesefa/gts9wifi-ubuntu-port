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

        page.add(this._keyboardGroup());
        window.add(page);
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
