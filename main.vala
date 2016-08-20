/* -*- Mode: Vala; indent-tabs-mode: nil; tab-width: 4 -*-
 * -*- coding: utf-8 -*-
 *
 * Copyright (C) 2011 ~ 2016 Deepin, Inc.
 *               2011 ~ 2016 Wang Yong
 *
 * Author:     Wang Yong <wangyong@deepin.com>
 * Maintainer: Wang Yong <wangyong@deepin.com>
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */ 

using Gtk;
using Gdk;
using Vte;
using Widgets;
using Keymap;
using Wnck;

[DBus (name = "com.deepin.terminal")]
public class TerminalApp : Application {
    public static void on_bus_acquired(DBusConnection conn, TerminalApp app) {
        try {
            conn.register_object("/com/deepin/terminal", app);
        } catch (IOError e) {
            stderr.printf("Could not register service\n");
        }
    }
}

[DBus (name = "com.deepin.quake_terminal")]
public class QuakeTerminalApp : Application {
    public static void on_bus_acquired(DBusConnection conn, QuakeTerminalApp app) {
        try {
            conn.register_object("/com/deepin/quake_terminal", app);
        } catch (IOError e) {
            stderr.printf("Could not register service\n");
        }
    }
    
    public void show_or_hide() {
        this.quake_window.toggle_quake_window();
    }
}

[DBus (name = "com.deepin.quake_terminal")]
interface QuakeDaemon : Object {
    public abstract void show_or_hide() throws IOError;
}


public class Application : Object {
    public Widgets.Window window;
    public Widgets.QuakeWindow quake_window;
    public WorkspaceManager workspace_manager;
    
    private static bool version = false;
	private static bool quake_mode = false;
	private static string? work_directory = null;
    
    /* command_e (-e) is used for running commands independently (not inside a shell) */
    [CCode (array_length = false, array_null_terminated = true)]
	private static string[]? commands = null;
    private static string title = null;
	
	private const GLib.OptionEntry[] options = {
		{ "version", 0, 0, OptionArg.NONE, ref version, "Print version info and exit", null },
		{ "work-directory", 'w', 0, OptionArg.FILENAME, ref work_directory, "Set shell working directory", "DIRECTORY" },
		{ "quake-mode", 0, 0, OptionArg.NONE, ref quake_mode, "Quake mode", null },
        { "execute", 'e', 0, OptionArg.STRING_ARRAY, ref commands, "Run a program in terminal", "" },
		{ "execute", 'x', 0, OptionArg.STRING_ARRAY, ref commands, "Same as -e", "" },
		{ "execute", 'T', 0, OptionArg.STRING_ARRAY, ref title, "Title, just for compliation", "" },
        
		// list terminator
		{ null }
	};
    
    public void run(bool has_start) {
        if (has_start && quake_mode) {
            try {
                QuakeDaemon daemon = Bus.get_proxy_sync(BusType.SESSION, "com.deepin.quake_terminal", "/com/deepin/quake_terminal");
                daemon.show_or_hide();
            } catch (IOError e) {
                stderr.printf("%s\n", e.message);
            }
            
            Gtk.main_quit();
        } else {
            Utils.load_css_theme(Utils.get_root_path("style.css"));
            
            Tabbar tabbar = new Tabbar();
            workspace_manager = new WorkspaceManager(tabbar, commands, work_directory); 
            
            tabbar.press_tab.connect((t, tab_index, tab_id) => {
					tabbar.unhighlight_tab(tab_id);
					workspace_manager.switch_workspace(tab_id);
                });
            tabbar.close_tab.connect((t, tab_index, tab_id) => {
                    Widgets.Workspace focus_workspace = workspace_manager.workspace_map.get(tab_id);
                    if (focus_workspace.has_active_term()) {
                        ConfirmDialog dialog;
                        if (quake_mode) {
                            dialog = Widgets.create_running_confirm_dialog(quake_window);
                        } else {
                            dialog = Widgets.create_running_confirm_dialog(window);
                        }
                        dialog.confirm.connect((d) => {
                                tabbar.destroy_tab(tab_index);
                                workspace_manager.remove_workspace(tab_id);
                            });
                    } else {
                        tabbar.destroy_tab(tab_index);
                        workspace_manager.remove_workspace(tab_id);
                    }
                });
            tabbar.new_tab.connect((t) => {
                    workspace_manager.new_workspace_with_current_directory();
                });
            
            Box box = new Box(Gtk.Orientation.VERTICAL, 0);
            Box top_box = new Box(Gtk.Orientation.HORIZONTAL, 0);
            Gdk.RGBA background_color = Gdk.RGBA();
            
            if (quake_mode) {
                quake_window = new Widgets.QuakeWindow();
                quake_window.draw_active_tab_underline(tabbar);
                
                top_box.draw.connect((w, cr) => {
                        Gtk.Allocation rect;
                        w.get_allocation(out rect);
                        
                        try {
                            background_color.parse(quake_window.config.config_file.get_string("theme", "background"));
                            cr.set_source_rgba(background_color.red, background_color.green, background_color.blue, quake_window.config.config_file.get_double("general", "opacity"));
                            Draw.draw_rectangle(cr, 0, 0, rect.width, Constant.TITLEBAR_HEIGHT);
                        } catch (Error e) {
                            print("Main quake mode: %s\n", e.message);
                        }
                    
                        Utils.propagate_draw(top_box, cr);
                        
                        return true;
                    });
            
            
                quake_window.delete_event.connect((w) => {
                        quit();
                        
                        return true;
                    });
                quake_window.destroy.connect((t) => {
                        quit();
                    });
                quake_window.key_press_event.connect((w, e) => {
                        return on_key_press(w, e);
                    });
                quake_window.focus_out_event.connect((w) => {
                        quake_window.remove_shortcut_viewer();
                        
                        return false;
                    });
                quake_window.key_release_event.connect((w, e) => {
                        return on_key_release(w, e);
                    });
                
                box.pack_start(workspace_manager, true, true, 0);
                Widgets.EventBox event_box = new Widgets.EventBox();
                top_box.pack_start(tabbar, true, true, 0);
                event_box.add(top_box);
                box.pack_start(event_box, false, false, 0);
                
                // First focus terminal after show quake terminal.
                // Sometimes, some popup window (like wine program's popup notify window) will grab focus,
                // so call window.present to make terminal get focus.
                quake_window.show.connect((t) => {
                        quake_window.present();
                    });
                
                quake_window.add_widget(box);
                quake_window.show_all();
            } else {
                window = new Widgets.Window();
                Appbar appbar = new Appbar(window, tabbar, this, workspace_manager);
                var overlay = new Gtk.Overlay();
                
                appbar.set_valign(Gtk.Align.START);
                
                var fullscreen_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
                top_box.pack_start(fullscreen_box, false, false, 0);
                
                var spacing_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);
                spacing_box.set_size_request(-1, Constant.TITLEBAR_HEIGHT);
                fullscreen_box.pack_start(spacing_box, false, false, 0);
                
                box.pack_start(top_box, false, false, 0);
                box.pack_start(workspace_manager, true, true, 0);
                
                appbar.close_window.connect((w) => {
                        quit();
                    });
                appbar.quit_fullscreen.connect((w) => {
                        window.toggle_fullscreen();
                    });
            
                window.draw_active_tab_underline(tabbar);
                
                window.delete_event.connect((w) => {
                        quit();
                        
                        return true;
                    });
                window.destroy.connect((t) => {
                        quit();
                    });
                window.window_state_event.connect((w) => {
                        appbar.update_max_button();
                    
                        return false;
                    });
                window.key_press_event.connect((w, e) => {
                        return on_key_press(w, e);
                    });
                window.key_release_event.connect((w, e) => {
                        return on_key_release(w, e);
                    });
                window.focus_out_event.connect((w) => {
                        window.remove_shortcut_viewer();
                        
                        return false;
                    });
                window.configure_event.connect((w) => {
                        workspace_manager.focus_workspace.remove_remote_panel();
                        
                        return false;
                    });
                
                if (!have_terminal_at_same_workspace()) {
                    window.set_position(Gtk.WindowPosition.CENTER);
                }

                window.configure_event.connect((w) => {
                        if (window.window_is_fullscreen()) {
                            Utils.remove_all_children(fullscreen_box);
                            appbar.hide();
                            appbar.hide_window_button();
                            window.draw_tabbar_line = false;
                        } else {
                            Gtk.Widget? parent = spacing_box.get_parent();
                            if (parent == null) {
                                fullscreen_box.pack_start(spacing_box, false, false, 0);
                                appbar.show_all();
                                appbar.show_window_button();
                                window.draw_tabbar_line = true;
                            }
                        }
                        
                        return false;
                    });
                
                window.motion_notify_event.connect((w, e) => {
                        if (window.window_is_fullscreen()) {
                            if (e.y_root < window.window_fullscreen_monitor_height) {
                                GLib.Timeout.add(window.window_fullscreen_monitor_timeout, () => {
                                        Gdk.Display gdk_display = Gdk.Display.get_default();
                                        var seat = gdk_display.get_default_seat();
                                        var device = seat.get_pointer();
                    
                                        int pointer_x, pointer_y;
                                        device.get_position(null, out pointer_x, out pointer_y);

                                        if (pointer_y < window.window_fullscreen_response_height) {
                                            appbar.show_all();
                                            window.draw_tabbar_line = true;
                                
                                            window.queue_draw();
                                        } else if (pointer_y > Constant.TITLEBAR_HEIGHT) {
                                            appbar.hide();
                                            window.draw_tabbar_line = false;                                
                                
                                            window.queue_draw();
                                        }
                                        
                                        return false;
                                    });
                            }
                        }
                        
                        return false;
                    });
                
                overlay.add(box);
                overlay.add_overlay(appbar);
			
                window.add_widget(overlay);
                window.show_all();
            }
        }
    }
    
    public bool have_terminal_at_same_workspace() {
        var screen = Wnck.Screen.get_default();
        screen.force_update();
        
        var active_workspace = screen.get_active_workspace();
        foreach (Wnck.Window window in screen.get_windows()) {
            var workspace = window.get_workspace();
            if (workspace.get_number() == active_workspace.get_number()) {
                if (window.get_name() == "deepin-terminal") {
                    return true;
                }
            }
        }
        
        return false;
    }
    
    public void quit() {
        if (workspace_manager.has_active_term()) {
            ConfirmDialog dialog = Widgets.create_running_confirm_dialog(window);
            dialog.confirm.connect((d) => {
                    Gtk.main_quit();
                });
        } else {
            Gtk.main_quit();
        }
    }
    
    private bool on_key_press(Gtk.Widget widget, Gdk.EventKey key_event) {
		try {
            string keyname = Keymap.get_keyevent_name(key_event);
            string[] ctrl_num_keys = {"Ctrl + 1", "Ctrl + 2", "Ctrl + 3", "Ctrl + 4", "Ctrl + 5", "Ctrl + 6", "Ctrl + 7", "Ctrl + 8", "Ctrl + 9"};
            
            KeyFile config_file;
            if (quake_mode) {
                config_file = quake_window.config.config_file;
            } else {
                config_file = window.config.config_file;
            }
		    
            var search_key = config_file.get_string("keybind", "search");
		    if (search_key != "" && keyname == search_key) {
		    	workspace_manager.focus_workspace.search();
		    	return true;
		    }
		    
		    var new_workspace_key = config_file.get_string("keybind", "new_workspace");
		    if (new_workspace_key != "" && keyname == new_workspace_key) {
				workspace_manager.new_workspace_with_current_directory();
				return true;
		    }
		    
		    var close_workspace_key = config_file.get_string("keybind", "close_workspace");
		    if (close_workspace_key != "" && keyname == close_workspace_key) {
		    	workspace_manager.tabbar.close_current_tab();
		    	return true;
		    }
		    	
		    var next_workspace_key = config_file.get_string("keybind", "next_workspace");
		    if (next_workspace_key != "" && keyname == next_workspace_key) {
		    	workspace_manager.tabbar.select_next_tab();
		    	return true;
		    }
		    	
		    var previous_workspace_key = config_file.get_string("keybind", "previous_workspace");
		    if (previous_workspace_key != "" && keyname == previous_workspace_key) {
		    	workspace_manager.tabbar.select_previous_tab();
		    	return true;
		    }
		    
		    var split_vertically_key = config_file.get_string("keybind", "split_vertically");
		    if (split_vertically_key != "" && keyname == split_vertically_key) {
		    	workspace_manager.focus_workspace.split_vertical();
		    	return true;
		    }
		    
		    var split_horizontally_key = config_file.get_string("keybind", "split_horizontally");
		    if (split_horizontally_key != "" && keyname == split_horizontally_key) {
		    	workspace_manager.focus_workspace.split_horizontal();
		    	return true;
		    }
		    
		    var select_up_window_key = config_file.get_string("keybind", "select_up_window");
		    if (select_up_window_key != "" && keyname == select_up_window_key) {
		    	workspace_manager.focus_workspace.select_up_window();
		    	return true;
		    }
		    
		    var select_down_window_key = config_file.get_string("keybind", "select_down_window");
		    if (select_down_window_key != "" && keyname == select_down_window_key) {
		    	workspace_manager.focus_workspace.select_down_window();
		    	return true;
		    }
		    
		    var select_left_window_key = config_file.get_string("keybind", "select_left_window");
		    if (select_left_window_key != "" && keyname == select_left_window_key) {
		    	workspace_manager.focus_workspace.select_left_window();
		    	return true;
		    }
		    
		    var select_right_window_key = config_file.get_string("keybind", "select_right_window");
		    if (select_right_window_key != "" && keyname == select_right_window_key) {
		    	workspace_manager.focus_workspace.select_right_window();
		    	return true;
		    }
		    
		    var close_window_key = config_file.get_string("keybind", "close_window");
		    if (close_window_key != "" && keyname == close_window_key) {
		    	workspace_manager.focus_workspace.close_focus_term();
		    	return true;
		    }
		    
		    var close_other_windows_key = config_file.get_string("keybind", "close_other_windows");
		    if (close_other_windows_key != "" && keyname == close_other_windows_key) {
		    	workspace_manager.focus_workspace.close_other_terms();
		    	return true;
		    }
		    
		    var toggle_fullscreen_key = config_file.get_string("keybind", "toggle_fullscreen");
		    if (toggle_fullscreen_key != "" && keyname == toggle_fullscreen_key) {
		    	if (!quake_mode) {
		    		window.toggle_fullscreen();
		    	}
		    	return true;
		    }
		    
            if (Utils.is_command_exist("deepin-shortcut-viewer")) {
                var show_helper_window_key = config_file.get_string("keybind", "show_helper_window");
                if (show_helper_window_key != "" && keyname == show_helper_window_key) {
                    int x, y;
                    if (quake_mode) {
                        Gdk.Screen screen = Gdk.Screen.get_default();
                        int monitor = screen.get_monitor_at_window(screen.get_active_window());
                        Gdk.Rectangle rect;
                        screen.get_monitor_geometry(monitor, out rect);
                        
                        x = rect.width / 2;
                        y = rect.height / 2;
                        
                        quake_window.show_shortcut_viewer(x, y);
                    } else {
                        Gtk.Allocation window_rect;
                        window.get_allocation(out window_rect);

                        int win_x, win_y;
                        window.get_window().get_origin(out win_x, out win_y);
                        
                        x = win_x + window_rect.width / 2;
                        y = win_y + window_rect.height / 2;
                        window.show_shortcut_viewer(x, y);
                    }
                
                    return true;
                }
            }
            
		    var show_remote_panel_key = config_file.get_string("keybind", "show_remote_panel");
		    if (show_remote_panel_key != "" && keyname == show_remote_panel_key) {
		    	workspace_manager.focus_workspace.toggle_remote_panel(workspace_manager.focus_workspace);
		    	return true;
		    }
		    
		    var select_all_key = config_file.get_string("keybind", "select_all");
		    if (select_all_key != "" && keyname == select_all_key) {
		    	workspace_manager.focus_workspace.toggle_select_all();
		    	return true;
		    }
		    
		    if (keyname in ctrl_num_keys) {
                workspace_manager.switch_workspace_with_index(int.parse(Keymap.get_key_name(key_event.keyval)));
		    	return true;
            }
            
            return false;
		} catch (GLib.KeyFileError e) {
			print("Main on_key_press: %s\n", e.message);
			
			return false;
		}
    }
    
    private bool on_key_release(Gtk.Widget widget, Gdk.EventKey key_event) {
        if (Keymap.is_no_key_press(key_event)) {
            if (Utils.is_command_exist("deepin-shortcut-viewer")) {
                if (quake_mode) {
                    quake_window.remove_shortcut_viewer();
                } else {
                    window.remove_shortcut_viewer();
                }
            }
        }
        
        return false;
    }
    
    public static void main(string[] args) {
        // NOTE: Parse option '-e' or '-x' by myself.
        // OptionContext's function always lost argument after option '-e' or '-x'.
        string[] argv;
        string command = "";

        foreach (string a in args[1:args.length]) {
            command = command + " " + a;
        }

        try {
            Shell.parse_argv(command, out argv);
        } catch (ShellError e) {
            if (!(e is ShellError.EMPTY_STRING)) {
                warning("Main main: %s\n", e.message);
            }
        }
        bool start_parse_command = false;
        string user_command = "";
        foreach (string arg in argv) {
            if (arg == "-e" || arg == "-x") {
                start_parse_command = true;
            } else if (arg.has_prefix("-")) {
                if (start_parse_command) {
                    start_parse_command = false;
                }
            } else {
                if (start_parse_command) {
                    user_command = user_command + " " + arg;
                }
            }
            
        }
        
        
        try {
			var opt_context = new OptionContext();
			opt_context.set_help_enabled(true);
			opt_context.add_main_entries(options, null);
			opt_context.parse(ref args);
		} catch (OptionError e) {
			stdout.printf ("error: %s\n", e.message);
			stdout.printf ("Run '%s --help' to see a full list of available command line options.\n", args[0]);
		}
        
        // User 'user_command' instead OptionContext's 'commands'.
        try {
            Shell.parse_argv(user_command, out commands);
        } catch (ShellError e) {
            if (!(e is ShellError.EMPTY_STRING)) {
                warning("Main main: %s\n", e.message);
            }
        }
        
        if (version) {
			stdout.printf("Deepin Terminal 2.0\n");
        } else {
            Gtk.init(ref args);
            
            if (quake_mode) {
                QuakeTerminalApp app = new QuakeTerminalApp();
                Bus.own_name(BusType.SESSION,
                             "com.deepin.quake_terminal",
                             BusNameOwnerFlags.NONE,
                             ((con) => {QuakeTerminalApp.on_bus_acquired(con, app);}),
                             () => {app.run(false);},
                             () => {app.run(true);});
            } else {
                TerminalApp app = new TerminalApp();
                Bus.own_name(BusType.SESSION,
                             "com.deepin.terminal",
                             BusNameOwnerFlags.NONE,
                             ((con) => {TerminalApp.on_bus_acquired(con, app);}),
                             () => {app.run(false);},
                             () => {app.run(true);});
            }
            
            Gtk.main();
        }
    }
}