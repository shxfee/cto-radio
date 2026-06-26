# cto-radio

> [!WARNING]
> **Experimental — not for public consumption.** This is a personal, single-listener
> hobby stream. It is **extremely unstable**: it drops, stutters, and goes silent
> without notice, and any public endpoint may vanish at any time. Don't depend on it,
> don't share the listen link, and don't treat any URL here as a service. Read it as a
> reference build, not a station you can tune into.

Turn a headless box into an **always-on Spotify Connect device** that streams whatever it plays to a webpage you can open anywhere.

Two problems this solves:

1. **Cold start.** Spotify can only start playback on a device that's *already open*. Close the app on your phone and the device vanishes — there's nothing to "press play" on. A headless [`go-librespot`](https://github.com/devgianlu/go-librespot) instance is a device that never sleeps, so you can start playback any time, from anything (the Spotify API, a script, your phone), with no app open first.
2. **Hearing it.** A headless server has no speakers. So the audio is piped out as a live HTTP stream you tune into from a browser, phone, or any media player.

```
go-librespot ──▶ FIFO (raw PCM) ──▶ ffmpeg ──▶ Icecast ──▶ http://you:8000/stream-<token>.mp3
                                                                        ▲
                                                                you, anywhere
```

No PulseAudio/PipeWire needed — audio goes straight through a named pipe.

## Pieces

| File | What it is |
|------|------------|
| `config.yml.example` | go-librespot config — device name, bitrate, pipe output, headless OAuth |
| `icecast.xml.example` | Icecast config — passwords, the mount, a silence fallback |
| `stream.env.example` | source password + mount token for the ffmpeg service |
| `listen.html` | a dark, self-reconnecting player page — shows cover art, title and progress |
| `cto-now.sh` | polls go-librespot and writes `now.json` into the webroot for the player |
| `cto-now.service` | `--user` service that runs the now-playing feeder |
| `systemd/*.service` | four `--user` services that keep the whole chain alive |

## Setup

Assumes Linux with `ffmpeg` and `icecast` installed, and the [go-librespot](https://github.com/devgianlu/go-librespot/releases) binary at `/usr/local/bin/go-librespot`.

**1. go-librespot config + first login**

```bash
mkdir -p ~/.config/go-librespot ~/.local/share/go-librespot
cp config.yml.example ~/.config/go-librespot/config.yml
# edit it: set your username path, device_name, bitrate
go-librespot         # prints an authorize URL
```

Open the URL in a browser logged into your Spotify account, approve, and the
redirect to `127.0.0.1` completes the login. Credentials cache to
`~/.config/go-librespot/state.json` — you only do this once. (Spotify Premium required.)

**2. Icecast**

```bash
sudo cp icecast.xml.example /etc/icecast.xml
# edit: set source/admin passwords, your hostname/IP, and an unguessable mount token
# generate a silence fallback so the mount stays alive during pauses:
ffmpeg -f lavfi -i anullsrc=r=44100:cl=stereo -t 5 -b:a 128k silence.mp3
sudo cp silence.mp3 /usr/share/icecast/web/silence.mp3
sudo systemctl enable --now icecast
```

**3. Player page** — drop `listen.html` in the Icecast webroot and point `SRC` at your mount:

```bash
sudo cp listen.html /usr/share/icecast/web/listen.html
# edit the SRC constant in it to /stream-<your-token>.mp3
```

**4. The services**

```bash
mkdir -p ~/.config/cto-stream
cp stream.env.example ~/.config/cto-stream/stream.env   # set SRC + LIS, then: chmod 600
chmod 600 ~/.config/cto-stream/stream.env

cp systemd/*.service ~/.config/systemd/user/
loginctl enable-linger "$USER"      # run without an active login
systemctl --user daemon-reload
systemctl --user enable --now cto-fifo cto-pipe-keeper go-librespot cto-stream
```

Now your box shows up in Spotify as a device. Play to it from anywhere, and open
`http://YOUR_IP:8000/listen.html` to hear it.

## Listening

The `listen.html` page is fine in a pinch, but **mobile browsers are the worst case for a live stream** — they buffer poorly and won't auto-resume after a stall. For a steady listen, use a real audio app and point it at the raw mount (`http://YOUR_IP:8000/stream-<token>.mp3`):

- **VLC** (any platform) — most bulletproof. *New stream* → paste the URL.
- **Transistor** (Android, F-Droid) — minimal, purpose-built for one custom radio URL.

Some apps choke on a bare `.mp3` and want a **playlist file**. Drop a `.pls` (and/or `.m3u`) in the Icecast webroot — it carries the station name *and* the stream URL, so the app shows a proper named station instead of nothing:

```bash
STREAM="http://YOUR_IP:8000/stream-<token>.mp3"

# .pls — most widely accepted by radio apps
printf '[playlist]\nNumberOfEntries=1\nFile1=%s\nTitle1=My box\nLength1=-1\nVersion=2\n' "$STREAM" \
  | sudo tee /usr/share/icecast/web/station.pls >/dev/null

# .m3u — alternative
printf '#EXTM3U\n#EXTINF:-1,My box\n%s\n' "$STREAM" \
  | sudo tee /usr/share/icecast/web/station.m3u >/dev/null
```

Then add `http://YOUR_IP:8000/station.pls` in the app. (`.pls` plays cleanly in VLC; if an app prefers the other, `.m3u` is right there.)

## How it holds together

- **The FIFO keeper** (`cto-pipe-keeper`) holds both ends of the named pipe open. Without it, when ffmpeg or go-librespot restarts the other side gets an EOF or `SIGPIPE` and dies. The keeper opens the FIFO read-write and just sits there — it never reads, so it steals no audio, it only keeps the pipe from ever signalling end-of-stream.
- **`source-timeout` is set high** (2h) so Icecast doesn't drop the source during a long pause. The `silence.mp3` fallback covers brief gaps so the mount URL never 404s.
- **The mount token is the secret.** The stream is at `/stream-<random>.mp3`; the unguessable path is what keeps it private while staying trivial to open in any player (no auth dialog). Rotate it by changing the mount name.
- **The player page reconnects itself** — a watchdog reopens the stream only if playback genuinely stalls for 15s, and it resumes when you unlock your phone. It deliberately does *not* reconnect on every transient `stalled` event (that just causes endless rebuffering).

## Notes

- High latency between your server and your phone? Drop the ffmpeg bitrate (`-b:a`) to 128k — plenty for casual listening and far kinder to thin mobile buffers.
- `go-librespot` also stays LAN-discoverable (zeroconf), so a phone on the same network can hand off to it directly.

---

Built one evening, for the joy of it.
