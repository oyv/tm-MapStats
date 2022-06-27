// Copyright (c) 2022 Øyvind Rønningstad

#if TMNEXT

[Setting name="Display limit" description="The maximum amount of maps to display in the menu."]
int Setting_DisplayLimit = 10;

class MapStats
{
	string m_uid;
	string m_name;

	uint64 m_timePlay = 0;
	uint64 m_timeEditor = 0;
	uint64 m_timeSpectator = 0;

	MapStats(const Json::Value &in js)
	{
		FromJson(js);
	}

	MapStats(const string &in uid, const Json::Value &in js)
	{
		m_uid = uid;
		FromJson(js);
	}

	MapStats(const string &in uid, const string &in name)
	{
		m_uid = uid;
		m_name = name;
	}

	void FromJson(const Json::Value &in js)
	{
		if (js.HasKey("uid")) {
			m_uid = js["uid"];
		}
		m_name = js["name"];
		m_timePlay = Text::ParseUInt64(js["play_time"]);
		m_timeEditor = Text::ParseUInt64(js["editor_time"]);
		m_timeSpectator = Text::ParseUInt64(js["spectator_time"]);
	}

	Json::Value ToJson()
	{
		auto ret = Json::Object();
		ret["uid"] = m_uid;
		ret["name"] = m_name;
		ret["play_time"] = Text::Format("%lld", m_timePlay);
		ret["editor_time"] = Text::Format("%lld", m_timeEditor);
		ret["spectator_time"] = Text::Format("%lld", m_timeSpectator);
		return ret;
	}
}

array<MapStats@> g_maps;

int FindMapStats(const string &in uid)
{
	// We look for UID in reverse here because recent maps are last!
	for (int i = int(g_maps.Length) - 1; i >= 0; i--) {
		auto ms = g_maps[i];
		if (ms.m_uid == uid) {
			return int(i);
		}
	}
	return -1;
}

uint64 prev_time; // The previous timestamp at which the time was saved.
uint64 prev_game_time = 0;
bool current_editor = false;
bool current_spectator = false;
string current_map = "";

uint64 save_interval = 60000; // 60 seconds
uint64 sleep_interval = 1000; // 1 second
auto path = IO::FromDataFolder("map_stats.json");

void save_time(const string &in uid, const string &in map_name, uint64 add_time, bool editor, bool spectator, bool to_file)
{
	MapStats@ ms = null;

	int index = FindMapStats(uid);
	if (index == -1) {
		@ms = MapStats(uid, map_name);
	} else {
		@ms = g_maps[index];
		g_maps.RemoveAt(index);
	}
	g_maps.InsertLast(ms);

	if (spectator) {
		ms.m_timeSpectator += add_time;
	} else if (editor) {
		ms.m_timeEditor += add_time;
	} else {
		ms.m_timePlay += add_time;
	}

	if (to_file) {
		auto path = IO::FromDataFolder("map_stats.json");

		auto jsMaps = Json::Array();
		for (uint i = 0; i < g_maps.Length; i++) {
			jsMaps.Add(g_maps[i].ToJson());
		}

		auto js = Json::Object();
		js["version"] = 2;
		js["maps"] = jsMaps;

		Json::ToFile(path, js);
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
		auto js = Json::FromFile(path);

		int version = 1;
		if (js.HasKey("version")) {
			version = js["version"];
		}

		if (version == 1) {
			// Migrate from old format
			auto keys = js["maps"].GetKeys();
			for (uint i = 0; i < keys.Length; i++) {
				string uid = keys[i];
				g_maps.InsertLast(MapStats(uid, js["maps"][uid]));
			}

		} else {
			// Load new format
			auto jsMaps = js["maps"];
			for (uint i = 0; i < jsMaps.Length; i++) {
				g_maps.InsertLast(MapStats(jsMaps[i]));
			}
		}

		trace("Loaded " + g_maps.Length + " maps from disk");
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
		int lowestIndex = int(g_maps.Length) - Setting_DisplayLimit;
		if (lowestIndex < 0) {
			lowestIndex = 0;
		}

		for (int i = int(g_maps.Length) - 1; i >= lowestIndex; i--) {
			auto ms = g_maps[i];

			string map_name = "No map";
			if (ms.m_name != "") {
				map_name = ms.m_name;
			}

			uint64 play_time = ms.m_timePlay;
			uint64 editor_time = ms.m_timeEditor;
			uint64 spectator_time = ms.m_timeSpectator;

			if (ms.m_uid == current_map) {
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

			UI::TextWrapped(ColoredString(map_name));
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
