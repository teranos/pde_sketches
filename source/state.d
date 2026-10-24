module state;

import std.conv : to;
import std.format : format;
import std.string : join, split, strip;

/// The pad drives Processing sketches on the right side. This process speaks
/// ramen's sockets and holds what the pad has set; bin/renderer is a
/// Processing program that draws whatever state it is handed into the frame
/// file, and says `f` each time a frame is in.
enum name = "sketches";

immutable string[5] pages = ["particles", "lines", "startfield", "scene", "walker"];
enum scenePage = 3;
enum walkerPage = 4;

/// The middle row, left to right, per page. The scene's row is its params.
immutable string[3][pages.length] paramNames = [
    ["count", "speed", "size"],
    ["count", "speed", "twist"],
    ["stars", "speed", "trail"],
    ["hue", "saturation", "scale"],
    ["walkers", "diagonals", "triangles"],
];

/// What the scene's bottom row pages between, and what any of them takes.
immutable string[5] things = ["sky", "ground", "trunks", "lake", "mist"];
immutable string[3] sceneParams = paramNames[scenePage];

/// One knob detent moves every locked parameter this far, on 0..1.
enum step = 0.02;

/// One knob detent of time: a day is 96 of them, 15 minutes each.
enum timeStep = 1.0 / 96;

/// One whole day of the scene, in seconds.
enum cycleSeconds = 180.0;

struct State
{
    size_t page;
    /// Per page. The scene's row is unused: it keeps its values per thing.
    double[3][pages.length] value = [[0.4, 0.3, 0.3], [0.3, 0.3, 0.4], [0.5, 0.3, 0.3], [0.5, 0.5, 0.5], [0.3, 0.5, 0.2]];
    bool[3][pages.length] locked;
    double walkerSpeed = 0.4; /// the walker's wheel, while nothing on its page is locked
    double walkerImage = 0; /// how much of the picture the walker follows shows through, 0..1
    bool imageHeld; /// BL: the walker's wheel sets the picture's opacity
    bool walkerPaused; /// BC: the walkers stand still
    bool[3] middleDown; /// the middle row, as the pad holds it
    bool[3] middleToggled; /// of those, the ones whose press changed a lock
    uint width, height;

    double time = 0.22; /// of the day, 0..1, from midnight
    size_t thing;
    bool thingLocked;
    double[3][things.length] sceneValue = 0.5;
    bool[3][things.length] sceneLocked;

    /// A locked thing holds the clock.
    bool running() const
    {
        return !thingLocked;
    }

    /// One line, for the state file that carries it across a relaunch.
    string save() const
    {
        string[] f = [page.to!string];
        foreach (p; 0 .. 3)
            foreach (i; 0 .. 3)
                f ~= format("%.4f", value[p][i]);
        foreach (p; 0 .. 3)
            foreach (i; 0 .. 3)
                f ~= locked[p][i] ? "1" : "0";
        f ~= [format("%.6f", time), thing.to!string, thingLocked ? "1" : "0"];
        foreach (t; 0 .. things.length)
            foreach (i; 0 .. 3)
                f ~= format("%.4f", sceneValue[t][i]);
        foreach (t; 0 .. things.length)
            foreach (i; 0 .. 3)
                f ~= sceneLocked[t][i] ? "1" : "0";
        foreach (i; 0 .. 3)
            f ~= format("%.4f", value[walkerPage][i]);
        foreach (i; 0 .. 3)
            f ~= locked[walkerPage][i] ? "1" : "0";
        f ~= format("%.4f", walkerSpeed);
        f ~= [format("%.4f", walkerImage), imageHeld ? "1" : "0"];
        return f.join(" ");
    }

    /// Reads a line from before the scene (19 fields), from when it had
    /// three things (40), from before the walker (52), from before its
    /// picture (59), and as it is now (61).
    static State load(string line)
    {
        State st;
        auto f = line.strip.split;
        string[] walker;
        string[] image;
        if (f.length == 19 + 3 + things.length * 6 + 7 + 2)
        {
            image = f[$ - 2 .. $];
            f = f[0 .. $ - 2];
        }
        if (f.length == 19 + 3 + things.length * 6 + 7)
        {
            walker = f[$ - 7 .. $];
            f = f[0 .. $ - 7];
        }
        size_t n;
        if (f.length == 40)
            n = 3;
        else if (f.length == 19 + 3 + things.length * 6)
            n = things.length;
        else if (f.length != 19)
            return st;
        try
        {
            st.page = f[0].to!size_t % pages.length;
            foreach (p; 0 .. 3)
                foreach (i; 0 .. 3)
                {
                    st.value[p][i] = f[1 + p * 3 + i].to!double;
                    st.locked[p][i] = f[10 + p * 3 + i] == "1";
                }
            if (n)
            {
                st.time = f[19].to!double;
                st.thing = f[20].to!size_t % things.length;
                st.thingLocked = f[21] == "1";
                foreach (t; 0 .. n)
                    foreach (i; 0 .. 3)
                    {
                        st.sceneValue[t][i] = f[22 + t * 3 + i].to!double;
                        st.sceneLocked[t][i] = f[22 + n * 3 + t * 3 + i] == "1";
                    }
            }
            if (walker.length)
            {
                foreach (i; 0 .. 3)
                {
                    st.value[walkerPage][i] = walker[i].to!double;
                    st.locked[walkerPage][i] = walker[3 + i] == "1";
                }
                st.walkerSpeed = walker[6].to!double;
            }
            if (image.length)
            {
                st.walkerImage = image[0].to!double;
                st.imageHeld = image[1] == "1";
            }
        }
        catch (Exception)
            return State.init;
        return st;
    }

    /// What the renderer is told: the page and what it draws, nothing else.
    string forRenderer() const
    {
        if (page == scenePage)
        {
            string[] f = ["scene", format("%.6f", time), running ? "1" : "0",
                thing.to!string, thingLocked ? "1" : "0"];
            foreach (t; 0 .. things.length)
                foreach (i; 0 .. 3)
                    f ~= format("%.4f", sceneValue[t][i]);
            foreach (t; 0 .. things.length)
                foreach (i; 0 .. 3)
                    f ~= sceneLocked[t][i] ? "1" : "0";
            return f.join(" ");
        }
        if (page == walkerPage)
            return format("walker %.4f %.4f %.4f %.4f %d %d %d %.4f %d %d", walkerSpeed,
                    value[walkerPage][0], value[walkerPage][1], value[walkerPage][2],
                    locked[walkerPage][0], locked[walkerPage][1], locked[walkerPage][2],
                    walkerImage, imageHeld, walkerPaused);
        return format("state %s %.4f %.4f %.4f %d %d %d", pages[page],
                value[page][0], value[page][1], value[page][2],
                locked[page][0], locked[page][1], locked[page][2]);
    }

    /// The clock, when it runs.
    void advance(double seconds)
    {
        if (running)
            time = wrapDay(time + seconds / cycleSeconds);
    }
}

double wrapDay(double t)
{
    import std.math : floor;

    return t - floor(t);
}

/// What a word did, so the caller knows what to say back.
enum Change
{
    none,
    size,
    page,
    lock,
    value,
    time,
    thing,
    thingLock,
    reset,
    image,
    pause,
    snapshot,
}

size_t middle(string key)
{
    return key == "ML" ? 0 : key == "MC" ? 1 : 2;
}

/// Raw pad edges, not the paged words: `down ML` is the key itself, where
/// `slower` is also what the knob says with BL held.
Change handle(ref State st, string msg)
{
    import std.algorithm : clamp;

    auto w = msg.strip.split;
    if (w.length == 3 && w[0] == "size")
    {
        uint nw, nh;
        try
        {
            nw = w[1].to!uint;
            nh = w[2].to!uint;
        }
        catch (Exception)
            return Change.none;
        if (nw == st.width && nh == st.height)
            return Change.none;
        st.width = nw;
        st.height = nh;
        return Change.size;
    }
    const scene = st.page == scenePage;
    if (w.length == 2 && w[0] == "down")
    {
        switch (w[1])
        {
        // "TL page left"
        case "TL":
            st.page = (st.page + pages.length - 1) % pages.length;
            return Change.page;
        // "TR page right"
        case "TR":
            st.page = (st.page + 1) % pages.length;
            return Change.page;
        // "middle row the three are each a parameter that can be locked"
        case "ML":
        case "MC":
        case "MR":
            const i = middle(w[1]);
            st.middleDown[i] = true;
            // On any page ML and MR together take a snapshot. The first of them
            // may have locked its parameter already, and gives it back.
            if (i != 1)
            {
                const other = i == 0 ? 2 : 0;
                if (st.middleDown[other])
                {
                    if (st.middleToggled[other])
                    {
                        if (scene)
                            st.sceneLocked[st.thing][other] = !st.sceneLocked[st.thing][other];
                        else
                            st.locked[st.page][other] = !st.locked[st.page][other];
                        st.middleToggled[other] = false;
                    }
                    return Change.snapshot;
                }
            }
            if (!scene)
            {
                st.locked[st.page][i] = !st.locked[st.page][i];
                st.middleToggled[i] = true;
                return Change.lock;
            }
            // "and while locked, middle row lets you select params like we have now"
            if (!st.thingLocked)
                return Change.none;
            st.sceneLocked[st.thing][i] = !st.sceneLocked[st.thing][i];
            st.middleToggled[i] = true;
            return Change.lock;
        case "BL":
        case "BR":
            // On the walker page BL hands the wheel to the picture's opacity.
            if (w[1] == "BL" && st.page == walkerPage)
            {
                st.imageHeld = !st.imageHeld;
                return Change.image;
            }
            // On the walker page BR starts the walk over.
            if (w[1] == "BR" && st.page == walkerPage)
                return Change.reset;
            // The scene's pager, between things, while none is locked.
            if (!scene || st.thingLocked)
                return Change.none;
            st.thing = (st.thing + (w[1] == "BL" ? things.length - 1 : 1)) % things.length;
            return Change.thing;
        // "bottom middle key will unlock you again, let time continue"
        case "BC":
            // On the walker page BC stops the walkers, and starts them again.
            if (st.page == walkerPage)
            {
                st.walkerPaused = !st.walkerPaused;
                return Change.pause;
            }
            if (!scene)
                return Change.none;
            st.thingLocked = !st.thingLocked;
            return Change.thingLock;
        default:
            return Change.none;
        }
    }
    if (w.length == 2 && w[0] == "up")
    {
        if (w[1] == "ML" || w[1] == "MC" || w[1] == "MR")
        {
            st.middleDown[middle(w[1])] = false;
            st.middleToggled[middle(w[1])] = false;
        }
        return Change.none;
    }
    if (w.length == 2 && w[0] == "turn")
    {
        const dir = w[1] == "cw" ? 1 : -1;
        if (scene && !st.thingLocked)
        {
            // Nothing locked in the scene: the wheel is time.
            st.time = wrapDay(st.time + dir * timeStep);
            return Change.time;
        }
        if (st.page == walkerPage && st.imageHeld)
        {
            st.walkerImage = clamp(st.walkerImage + dir * step, 0.0, 1.0);
            return Change.value;
        }
        // The walker's wheel is its speed until one of its parameters is locked.
        if (st.page == walkerPage && !(st.locked[walkerPage][0] || st.locked[walkerPage][1] || st.locked[walkerPage][2]))
        {
            st.walkerSpeed = clamp(st.walkerSpeed + dir * step, 0.0, 1.0);
            return Change.value;
        }
        // Every locked parameter moves together.
        bool moved;
        foreach (i; 0 .. 3)
        {
            const on = scene ? st.sceneLocked[st.thing][i] : st.locked[st.page][i];
            auto v = scene ? &st.sceneValue[st.thing][i] : &st.value[st.page][i];
            if (on)
            {
                *v = clamp(*v + dir * step, 0.0, 1.0);
                moved = true;
            }
        }
        return moved ? Change.value : Change.none;
    }
    return Change.none;
}

unittest
{
    State st;
    assert(st.handle("down TL") == Change.page && st.page == walkerPage, "TL wraps left to the last page");
    assert(st.handle("down TR") == Change.page && st.page == 0);
    assert(st.handle("down TR") == Change.page && st.page == 1);
    st.page = 0;

    // Nothing locked: the knob moves nothing.
    const before = st.value;
    assert(st.handle("turn cw") == Change.none && st.value == before);

    // ML and MR locked: one detent moves exactly those two, MC stays.
    st.handle("down ML");
    st.handle("up ML");
    st.handle("down MR");
    st.handle("up MR");
    st.handle("turn cw");
    assert(st.value[0][0] == before[0][0] + step);
    assert(st.value[0][1] == before[0][1]);
    assert(st.value[0][2] == before[0][2] + step);

    // A lock belongs to its page: page right, the knob moves nothing there.
    st.handle("down TR");
    assert(st.handle("turn cw") == Change.none);
    st.handle("down TL");

    // Unlocking takes a parameter back out of the turn.
    st.handle("down ML");
    st.handle("up ML");
    st.handle("turn ccw");
    assert(st.value[0][0] == before[0][0] + step);
    assert(st.value[0][2] == before[0][2]);

    // Clamped to 0..1.
    foreach (_; 0 .. 200)
        st.handle("turn cw");
    assert(st.value[0][2] == 1.0);

    // The bottom row is free outside the scene.
    foreach (key; ["BL", "BC", "BR"])
        assert(st.handle("down " ~ key) == Change.none);

    // The paged words are not this source's: they move nothing.
    foreach (word; ["in", "out", "next", "prev", "slower", "pause", "faster", "rerun", "paramPrev", "paramNext"])
        assert(st.handle(word) == Change.none);

    // A state survives the file it is carried in.
    st.time = 0.6;
    st.thing = 2;
    st.sceneLocked[1][2] = true;
    st.sceneValue[2][0] = 0.25;
    const back = State.load(st.save);
    assert(back.page == st.page && back.locked == st.locked);
    assert(back.thing == 2 && back.sceneLocked == st.sceneLocked && back.sceneValue == st.sceneValue);
    assert(back.time - 0.6 < 1e-6 && 0.6 - back.time < 1e-6);
    foreach (p; 0 .. 3)
        foreach (i; 0 .. 3)
            assert(back.value[p][i] - st.value[p][i] < 1e-4 && st.value[p][i] - back.value[p][i] < 1e-4);

    // A line from when the scene had three things keeps them; lake and mist
    // start at their defaults.
    State three;
    three.sceneValue[1][2] = 0.7;
    three.sceneLocked[2][0] = true;
    auto f = three.save.split;
    const forty = (f[0 .. 22] ~ f[22 .. 31] ~ f[37 .. 46]).join(" ");
    const was = State.load(forty);
    // Phobos 2.112's to!double can land an ulp off a decimal, so parsed values get a tolerance.
    assert(was.sceneValue[1][2] - 0.7 < 1e-4 && 0.7 - was.sceneValue[1][2] < 1e-4);
    assert(was.sceneLocked[2][0] && !was.sceneLocked[3][0]);
    assert(was.sceneValue[3] == [0.5, 0.5, 0.5] && was.sceneValue[4] == [0.5, 0.5, 0.5]);

    // A line from before the scene still loads, the scene at its defaults.
    const old = State.load("1 0.4 0.3 0.3 0.6 0.6 0.4 0.5 0.3 0.3 0 0 0 1 1 0 0 0 0");
    assert(old.page == 1 && old.value[1][0] - 0.6 < 1e-4 && 0.6 - old.value[1][0] < 1e-4);
    assert(old.locked[1][0] && old.time == State.init.time);
}

unittest
{
    State st;
    st.page = scenePage;

    // Time runs, and the wheel plays with it.
    assert(st.running);
    st.advance(cycleSeconds / 2);
    assert(st.time - 0.72 < 1e-9 && 0.72 - st.time < 1e-9);
    assert(st.handle("turn cw") == Change.time);
    assert(st.time - (0.72 + timeStep) < 1e-9);
    st.time = 0.995;
    st.handle("turn cw");
    assert(st.time < 0.01, "time wraps past midnight");
    st.handle("turn ccw");
    assert(st.time > 0.99, "and back");

    // Unlocked, the middle row is free and the bottom row pages.
    assert(st.handle("down ML") == Change.none);
    assert(st.handle("down BR") == Change.thing && st.thing == 1);
    assert(st.handle("down BL") == Change.thing && st.thing == 0);
    assert(st.handle("down BL") == Change.thing && st.thing == 4 && things[4] == "mist", "BL wraps to the last thing");
    assert(st.handle("down BL") == Change.thing && st.thing == 3 && things[3] == "lake");
    foreach (_; 0 .. 4)
        st.handle("down BR");
    assert(st.thing == 2, "lake, mist, sky, ground, trunks");

    // BC locks onto the thing: time stops, the pager stops.
    assert(st.handle("down BC") == Change.thingLock && st.thingLocked && !st.running);
    const t = st.time;
    st.advance(30);
    assert(st.time == t);
    assert(st.handle("down BR") == Change.none && st.thing == 2);

    // Locked, the middle row selects params and the wheel moves them, not time.
    st.handle("up ML");
    assert(st.handle("down ML") == Change.lock && st.sceneLocked[2][0]);
    st.handle("up ML");
    assert(st.handle("down MR") == Change.lock && st.sceneLocked[2][2]);
    st.handle("up MR");
    assert(st.handle("turn cw") == Change.value);
    assert(st.time == t);
    assert(st.sceneValue[2][0] == 0.5 + step && st.sceneValue[2][1] == 0.5 && st.sceneValue[2][2] == 0.5 + step);
    foreach (other; [0, 1, 3, 4])
        assert(st.sceneValue[other] == [0.5, 0.5, 0.5], "only that thing moves");

    // BC again: time continues, the wheel is time again, values stay.
    assert(st.handle("down BC") == Change.thingLock && st.running);
    assert(st.handle("turn cw") == Change.time);
    assert(st.sceneValue[2][0] == 0.5 + step);
}

unittest
{
    // ML and MR together are a snapshot on every page, and leave the locks as they were.
    State st;
    st.page = 1;
    assert(st.handle("down ML") == Change.lock && st.locked[1][0]);
    assert(st.handle("down MR") == Change.snapshot && !st.locked[1][0] && !st.locked[1][2]);
    st.handle("up ML");
    st.handle("up MR");
    assert(st.handle("down MR") == Change.lock && st.locked[1][2], "alone, each still locks");
    st.handle("up MR");

    st.page = scenePage;
    assert(st.handle("down ML") == Change.none, "the scene's unlocked middle row is free");
    assert(st.handle("down MR") == Change.snapshot);
    st.handle("up ML");
    st.handle("up MR");
    st.thingLocked = true;
    assert(st.handle("down MR") == Change.lock && st.sceneLocked[0][2]);
    assert(st.handle("down ML") == Change.snapshot && !st.sceneLocked[0][0] && !st.sceneLocked[0][2]);
}

unittest
{
    import std.algorithm : canFind;

    State st;
    st.page = walkerPage;

    // Its middle row locks and the wheel moves what is locked, as on the first three pages.
    assert(st.forRenderer == "walker 0.4000 0.3000 0.5000 0.2000 0 0 0 0.0000 0 0");
    assert(legend(st).canFind("turn: speed|page right|lock walkers|lock diagonals|lock triangles|image opacity|pause|reset"));

    // BC stops the walkers, and BC starts them again.
    assert(st.handle("down BC") == Change.pause && st.walkerPaused);
    assert(st.forRenderer == "walker 0.4000 0.3000 0.5000 0.2000 0 0 0 0.0000 0 1");
    assert(toast(st, Change.pause, "down BC") == "paused");
    assert(legend(st).canFind("|resume|reset"));
    assert(st.handle("down BC") == Change.pause && !st.walkerPaused);
    assert(toast(st, Change.pause, "down BC") == "walking");

    // ML and MR together take a snapshot and leave both parameters as they were.
    assert(st.handle("down ML") == Change.lock && st.locked[walkerPage][0]);
    assert(st.handle("down MR") == Change.snapshot && !st.locked[walkerPage][0] && !st.locked[walkerPage][2]);
    assert(toast(st, Change.snapshot, "down MR") == "snapshot saved");
    st.handle("up ML");
    st.handle("up MR");
    // Either order, and each alone still locks.
    assert(st.handle("down MR") == Change.lock && st.locked[walkerPage][2]);
    assert(st.handle("down ML") == Change.snapshot && !st.locked[walkerPage][2] && !st.locked[walkerPage][0]);
    st.handle("up MR");
    st.handle("up ML");
    assert(st.handle("down MR") == Change.lock && st.locked[walkerPage][2]);
    st.handle("up MR");
    assert(st.handle("down MR") == Change.lock && !st.locked[walkerPage][2]);
    st.handle("up MR");

    // Nothing locked: the wheel is the walker's speed, and BR starts it over.
    const speed = st.walkerSpeed;
    assert(st.handle("turn cw") == Change.value && st.walkerSpeed == speed + step);
    assert(st.value[walkerPage] == [0.3, 0.5, 0.2]);
    assert(st.handle("down BR") == Change.reset);
    assert(toast(st, Change.reset, "down BR") == "reset");

    // Locked, the wheel moves the parameter and leaves the speed alone.
    assert(st.handle("down MC") == Change.lock && st.locked[walkerPage][1]);
    assert(toast(st, Change.lock, "down MC") == "locked diagonals");
    assert(legend(st).canFind("turn: locked"));
    const diagonals = st.value[walkerPage][1];
    assert(st.handle("turn cw") == Change.value && st.value[walkerPage][1] == diagonals + step);
    assert(st.value[walkerPage][0] == 0.3 && st.value[walkerPage][2] == 0.2);
    assert(st.walkerSpeed == speed + step);

    // BL hands the wheel to the picture's opacity: it moves that alone, and BL gives it back.
    assert(st.handle("down BL") == Change.image && st.imageHeld);
    assert(toast(st, Change.image, "down BL") == "wheel: image opacity");
    assert(legend(st).canFind("turn: opacity") && legend(st).canFind("release opacity"));
    assert(st.handle("turn cw") == Change.value && st.walkerImage == step);
    assert(st.value[walkerPage][1] == diagonals + step && st.walkerSpeed == speed + step);
    assert(st.forRenderer == format("walker %.4f 0.3000 %.4f 0.2000 0 1 0 0.0200 1 0", st.walkerSpeed, st.value[walkerPage][1]));
    foreach (_; 0 .. 100)
        st.handle("turn cw");
    assert(st.walkerImage == 1.0, "clamped to 0..1");
    assert(st.handle("down BL") == Change.image && !st.imageHeld);
    assert(st.handle("turn cw") == Change.value && st.walkerImage == 1.0, "released: the wheel is the locked parameter again");

    // The pager reaches it from the scene and goes round to the first page.
    st.page = scenePage;
    assert(st.handle("down TR") == Change.page && st.page == walkerPage);
    assert(toast(st, Change.page, "down TR") == "walker");
    assert(st.handle("down TR") == Change.page && st.page == 0);
}

unittest
{
    State st;
    st.value[walkerPage] = [0.1, 0.2, 0.75];
    st.locked[walkerPage][0] = true;
    st.walkerSpeed = 0.9;
    st.walkerImage = 0.35;
    st.imageHeld = true;
    auto f = st.save.split;
    assert(f.length == 61);
    const back = State.load(st.save);
    assert(back.imageHeld && back.walkerImage - 0.35 < 1e-4 && 0.35 - back.walkerImage < 1e-4);
    assert(back.locked[walkerPage] == [true, false, false]);

    // A line from before the picture loads with it hidden and the wheel not on it.
    const before = State.load(f[0 .. 59].join(" "));
    assert(before.walkerSpeed - 0.9 < 1e-4 && before.walkerImage == 0 && !before.imageHeld);
    assert(back.walkerSpeed - 0.9 < 1e-4 && 0.9 - back.walkerSpeed < 1e-4);
    assert(back.value[walkerPage][2] - 0.75 < 1e-4 && 0.75 - back.value[walkerPage][2] < 1e-4);

    // A line from before the walker loads with it at its defaults.
    const old = State.load(f[0 .. 52].join(" "));
    assert(old.value[walkerPage] == State.init.value[walkerPage] && !old.locked[walkerPage][0]);
    assert(old.walkerSpeed == State.init.walkerSpeed);
}

/// TL, knob, TR / ML, MC, MR / BL, BC, BR.
string legend(ref const State st)
{
    string[9] f;
    f[0] = "page left";
    f[2] = "page right";
    if (st.page == scenePage && st.thingLocked)
    {
        f[1] = "turn: locked";
        foreach (i; 0 .. 3)
            f[3 + i] = (st.sceneLocked[st.thing][i] ? "unlock " : "lock ") ~ sceneParams[i];
        f[6] = f[8] = "free";
        f[7] = "unlock " ~ things[st.thing];
    }
    else if (st.page == scenePage)
    {
        f[1] = "turn: time";
        f[3] = f[4] = f[5] = "free";
        f[6] = "prev thing";
        f[7] = "lock " ~ things[st.thing];
        f[8] = "next thing";
    }
    else
    {
        f[1] = "turn: locked";
        foreach (i; 0 .. 3)
            f[3 + i] = (st.locked[st.page][i] ? "unlock " : "lock ") ~ paramNames[st.page][i];
        f[6] = f[7] = f[8] = "free";
        if (st.page == walkerPage)
        {
            const held = st.locked[walkerPage][0] || st.locked[walkerPage][1] || st.locked[walkerPage][2];
            f[1] = st.imageHeld ? "turn: opacity" : held ? "turn: locked" : "turn: speed";
            f[6] = st.imageHeld ? "release opacity" : "image opacity";
            f[7] = st.walkerPaused ? "resume" : "pause";
            f[8] = "reset";
        }
    }
    return "legend " ~ name ~ " " ~ f[].join("|");
}

/// The toast for a change, or null when it needs none.
string toast(ref const State st, Change c, string msg)
{
    final switch (c)
    {
    case Change.none, Change.size, Change.value, Change.time:
        return null;
    case Change.page:
        return pages[st.page];
    case Change.thing:
        return things[st.thing];
    case Change.thingLock:
        return st.thingLocked ? things[st.thing] ~ " locked, time stopped" : "time running";
    case Change.reset:
        return "reset";
    case Change.image:
        return st.imageHeld ? "wheel: image opacity" : "wheel: speed";
    case Change.pause:
        return st.walkerPaused ? "paused" : "walking";
    case Change.snapshot:
        return "snapshot saved";
    case Change.lock:
        const i = middle(msg.strip.split[1]);
        if (st.page == scenePage)
            return (st.sceneLocked[st.thing][i] ? "locked " : "unlocked ") ~ sceneParams[i];
        return (st.locked[st.page][i] ? "locked " : "unlocked ") ~ paramNames[st.page][i];
    }
}
