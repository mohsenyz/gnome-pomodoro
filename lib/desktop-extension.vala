/*
 * Copyright (c) 2017 gnome-pomodoro contributors
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 */

using GLib;


namespace Pomodoro
{
    [DBus (name = "org.gnome.Pomodoro.Extension")]
    private interface DesktopExtensionInterface : GLib.Object
    {
        public abstract string[] capabilities { owned get; }
    }


    public class DesktopExtension : GLib.Object, GLib.Initable
    {
        public Pomodoro.CapabilityGroup capabilities { get; construct set; }

        /* extension may vanish for a short time, eg when restarting gnome-shell */
        public uint timeout { get; set; default = 1000; }

        private DesktopExtensionInterface? proxy = null;
        private uint watcher_id = 0;
        private uint timeout_id = 0;

        construct
        {
            this.capabilities = new Pomodoro.CapabilityGroup ("extension");
        }

        public DesktopExtension (GLib.Cancellable? cancellable = null) throws GLib.Error
        {
            this.init (cancellable);
        }

        public new bool init (GLib.Cancellable? cancellable = null) throws GLib.Error
        {
            if (this.proxy == null) {
                this.proxy = GLib.Bus.get_proxy_sync<DesktopExtensionInterface>
                                       (GLib.BusType.SESSION,
                                        "org.gnome.Pomodoro.Extension",
                                        "/org/gnome/Pomodoro/Extension",
                                        GLib.DBusProxyFlags.NONE);
            }

            if (this.watcher_id == 0) {
                this.watcher_id = GLib.Bus.watch_name (
                                            GLib.BusType.SESSION,
                                            "org.gnome.Pomodoro.Extension",
                                            GLib.BusNameWatcherFlags.NONE,
                                            this.on_name_appeared,
                                            this.on_name_vanished);
            }

            return true;
        }

        private void on_name_appeared (GLib.DBusConnection connection,
                                       string              name,
                                       string              name_owner)
                     requires (this.proxy != null)
        {
            if (this.timeout_id != 0) {
                GLib.Source.remove (this.timeout_id);
                this.timeout_id = 0;
            }

            foreach (var capability_name in this.proxy.capabilities) {
                this.capabilities.add (new Pomodoro.Capability (capability_name));
            }
        }

        private void on_name_vanished (GLib.DBusConnection connection,
                                       string              name)
        {
            if (this.timeout_id != 0) {
                GLib.Source.remove (this.timeout_id);
                this.timeout_id = 0;
            }

            this.timeout_id = GLib.Timeout.add (this.timeout, () => {
                this.timeout_id = 0;

                this.capabilities.remove_all ();

                return GLib.Source.REMOVE;
            });
        }

        public override void dispose ()
        {
            if (this.timeout_id != 0) {
                GLib.Source.remove (this.timeout_id);
                this.timeout_id = 0;
            }

            if (this.watcher_id != 0) {
                GLib.Bus.unwatch_name (this.watcher_id);
                this.watcher_id = 0;
            }

            this.proxy = null;

            base.dispose ();
        }
    }
}
