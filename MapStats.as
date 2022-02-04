// Copyright (c) 2022 Øyvind Rønningstad

#if TMNEXT

Json::Value current_stats;

uint64 prev_time; // The previous timestamp at which the time was saved.
uint64 prev_game_time = 0;
bool current_editor = false;
bool current_spectator = false;
string current_map = "";

uint64 save_interval = 60000; // 60 seconds
uint64 sleep_interval = 1000; // 1 second
auto path = IO::FromDataFolder("map_stats.json");

void save_time(string map, string map_name, uint64 add_time, bool editor, bool spectator, bool to_file)
{
	if (!current_stats["maps"].HasKey(map)) {
		current_stats["maps"][map] = Json::Object();
		current_stats["maps"][map]["name"] = map_name;
		current_stats["maps"][map]["play_time"] = Text::Format("%lld", 0);
		current_stats["maps"][map]["editor_time"] = Text::Format("%lld", 0);
		current_stats["maps"][map]["spectator_time"] = Text::Format("%lld", 0);
	}

	string time_name;
	if (spectator) {
		time_name = "spectator_time";
	} else if (editor) {
		time_name = "editor_time";
	} else {
		time_name = "play_time";
	}

	auto prev_saved_time = Text::ParseUInt64(current_stats["maps"][map][time_name]);
	Json::Value current_map = current_stats["maps"][map];

	// To put the current map at the bottom. This sorts the maps by how recently they were used.
	current_stats["maps"].Remove(map);
	current_stats["maps"][map] = current_map;
	current_stats["maps"][map][time_name] = Text::Format("%lld", prev_saved_time + add_time);

	if (to_file) {
		auto path = IO::FromDataFolder("map_stats.json");
		Json::ToFile(path, current_stats);
	}
}


void OnDestroyed()
{
	uint64 now_time = Time::get_Now();
	save_time(current_map, "", now_time - prev_time, current_editor, current_spectator, true);
	prev_time = now_time;
}


void Main()
{
	auto app = cast<CTrackMania>(GetApp());
	prev_time = Time::get_Now();

	if (IO::FileExists(path)) {
		current_stats = Json::FromFile(path);
	} else {
		current_stats = Json::Object();
		current_stats["maps"] = Json::Object();
	}

	while(true) {
		auto map = app.RootMap;
		string map_uid = "";
		string map_name = "";
		bool editor = app.Editor !is null;
		bool spectator = false;
		auto playground = app.CurrentPlayground;

		if (playground !is null && playground.GameTerminals.Length > 0 && playground.GameTerminals[0].ControlledPlayer !is null) {
			auto SpectatorMode = playground.GameTerminals[0].ControlledPlayer.User.SpectatorMode;
			spectator = ((SpectatorMode == CGameNetPlayerInfo::ESpectatorMode::Watcher) || (SpectatorMode == CGameNetPlayerInfo::ESpectatorMode::LocalWatcher));

			// It seems like SpectatorMode is sometimes stuck, so do another check.
			if (playground.GameTerminals[0].GUIPlayer !is null && playground.GameTerminals[0].ControlledPlayer is playground.GameTerminals[0].GUIPlayer) {
				spectator = false;
				auto gui_player = cast<CSmPlayer>(playground.GameTerminals[0].GUIPlayer);
			}
		}

		if (map !is null) {
			map_uid = map.MapInfo.MapUid;
			map_name = map.MapInfo.Name;
		}

		uint64 now_time = Time::get_Now();

		if ((map_uid == current_map) && (editor == current_editor) && (spectator == current_spectator)) {
			// No change
			if ((now_time / save_interval) > (prev_time / save_interval)) {
				save_time(map_uid, map_name, now_time - prev_time, editor, spectator, true);
				prev_time = now_time;
			}
		} else {
			// Either the map changed, or the type (play/spectator/editor) changed.
			save_time(current_map, "", now_time - prev_time, current_editor, current_spectator, true);
			prev_time = now_time;
			current_map = map_uid;
			current_editor = editor;
			current_spectator = spectator;
			save_time(current_map, map_name, 0, current_editor, current_spectator, false);
		}

		sleep(sleep_interval - (now_time % sleep_interval));
	}
}


string format_time(uint64 time_ms)
{
	if (time_ms == 0) {
		return "";
	}
	return Time::Format(time_ms, false);
}


void RenderMenu()
{
	UI::SetNextWindowContentSize(600, 0);
	if (UI::BeginMenu(Icons::PieChart + " Map Stats")) {
		UI::Columns(4, "map stats");
		UI::Text("Map Name");
		UI::NextColumn();
		UI::Text("Play Time");
		UI::NextColumn();
		UI::Text("Spectator Time");
		UI::NextColumn();
		UI::Text("Editor Time");
		UI::NextColumn();
		UI::Separator();

		// List maps most recently used first.
		auto keys = current_stats["maps"].GetKeys();
		for (int i = keys.Length - 1; i >= 0 ; i--) {
			string map_name;

			if (current_stats["maps"][keys[i]]["name"] == "") {
				map_name = "No map";
			} else {
				map_name = ColoredString(current_stats["maps"][keys[i]]["name"]);
			}

			uint64 play_time = Text::ParseUInt64(current_stats["maps"][keys[i]]["play_time"]);
			uint64 editor_time = Text::ParseUInt64(current_stats["maps"][keys[i]]["editor_time"]);
			uint64 spectator_time = Text::ParseUInt64(current_stats["maps"][keys[i]]["spectator_time"]);

			if (keys[i] == current_map) {
				// Track the current unsaved time as well.
				uint64 now_time = Time::get_Now();

				if (current_editor) {
					editor_time = now_time - prev_time + editor_time;
				} else if (current_spectator) {
					spectator_time = now_time - prev_time + spectator_time;
				} else {
					play_time = now_time - prev_time + play_time;
				}
			}

			UI::TextWrapped(map_name);
			UI::NextColumn();
			UI::Text(format_time(play_time));
			UI::NextColumn();
			UI::Text(format_time(spectator_time));
			UI::NextColumn();
			UI::Text(format_time(editor_time));
			UI::NextColumn();
		}

		UI::Columns(1);
		UI::EndMenu();
	}
}

#endif
