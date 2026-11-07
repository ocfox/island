package main

type Timestamps struct {
	Start int64 `json:"start"`
	End   int64 `json:"end"`
}

type SpotifyData struct {
	Song        string     `json:"song"`
	Artist      string     `json:"artist"`
	Album       string     `json:"album,omitempty"`
	AlbumArtURL string     `json:"album_art_url"`
	TrackID     string     `json:"track_id"`
	Timestamps  Timestamps `json:"timestamps"`
}

type DesktopState struct {
	Workspace  string `json:"workspace"`
	Activity   string `json:"activity"`
	App        string `json:"app"`
	Brightness int    `json:"brightness"`
	Dark       bool   `json:"dark"`
	HDR        bool   `json:"hdr"`
	ScreenOn   bool   `json:"screen_on"`
	CPU        int    `json:"cpu"`
	GPU        int    `json:"gpu"`
}

type PresencePayload struct {
	Kind      string        `json:"kind"`
	Status    string        `json:"status"` // "online" | "idle"
	Online    bool          `json:"online"`
	Spotify   *SpotifyData  `json:"spotify"`
	Desktop   *DesktopState `json:"desktop"`
	UpdatedAt int64         `json:"updated_at"`
}

type IncomingMessage struct {
	Kind string `json:"kind"`
	From string `json:"from,omitempty"`
}
